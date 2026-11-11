#!/usr/bin/env python3
"""Builds the Grafana dashboard "Restauranty: traffic and security" (#14).

Writes k8s/monitoring/dashboard.yaml: a ConfigMap that holds the dashboard as
JSON. Grafana loads it by itself (label grafana_dashboard). To change the
dashboard, change this file, run it, and apply the result:

    python3 scripts/build-dashboard.py
    kubectl apply -f k8s/monitoring/dashboard.yaml

Each panel is one query:
  - PromQL for numbers from Prometheus (the backends' /metrics, kube-state-metrics)
  - LogQL for the Gateway's access log in Loki (one JSON line per request)
"""
import json
from pathlib import Path

PROMETHEUS = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}

# The Gateway's access log, only requests for the app (not for Grafana, which
# goes through the same Gateway). Each line is JSON (k8s/platform/
# nginx-gateway-fabric-values.yaml); "| json" turns its fields into labels:
# ip, host, method, path, status, duration, ... Lines that are not JSON
# (NGINX's own messages) are dropped by __error__="".
APP_HOST = "restauranty.aks.springlaughing.dev"
GATEWAY = (
    '{namespace="gateway", container="nginx"} '
    f'|= `"host":"{APP_HOST}"` | json | __error__=""'
)


class Layout:
    """Places panels left to right on a 24-column grid, new line when full."""

    def __init__(self):
        self.panels, self.x, self.y, self.row_height = [], 0, 0, 0

    def row(self, title):
        self._new_line()
        self._add({"type": "row", "title": title, "collapsed": False}, 24, 1)

    def add(self, panel, width, height=8):
        self._add(panel, width, height)

    def _add(self, panel, width, height):
        if self.x + width > 24:
            self._new_line()
        panel["id"] = len(self.panels) + 1
        panel["gridPos"] = {"x": self.x, "y": self.y, "w": width, "h": height}
        self.panels.append(panel)
        self.x += width
        self.row_height = max(self.row_height, height)

    def _new_line(self):
        if self.x:
            self.x, self.y, self.row_height = 0, self.y + self.row_height, 0


def graph(title, description, source, queries, unit="short"):
    """A time series panel. queries: list of (query, legend)."""
    return {
        "type": "timeseries", "title": title, "description": description,
        "datasource": source,
        "fieldConfig": {"defaults": {"unit": unit, "min": 0}, "overrides": []},
        "options": {"legend": {"showLegend": True, "displayMode": "list", "placement": "bottom"},
                    "tooltip": {"mode": "multi"}},
        "targets": [{"refId": chr(65 + i), "expr": q, "legendFormat": legend, "datasource": source}
                    for i, (q, legend) in enumerate(queries)],
    }


def number(title, description, queries, steps=None):
    """A stat panel: the latest value, big. queries: list of (query, legend)."""
    steps = steps or [{"color": "text", "value": None}]
    return {
        "type": "stat", "title": title, "description": description, "datasource": PROMETHEUS,
        "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": steps}}, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "value", "graphMode": "none", "textMode": "auto"},
        "targets": [{"refId": chr(65 + i), "expr": q, "legendFormat": legend, "datasource": PROMETHEUS}
                    for i, (q, legend) in enumerate(queries)],
    }


def colors(*steps):
    """Threshold colors: colors(("green", None), ("red", 10)) = green below 10, red from 10."""
    return [{"color": c, "value": v} for c, v in steps]


board = Layout()

# ---------------------------------------------------------------- traffic
board.row("Traffic: how busy, how broken, how slow")
board.add(graph(
    "Requests per second",
    "Requests that reached a backend, per service.",
    PROMETHEUS, [("sum by (job) (rate(http_requests_total[1m]))", "{{job}}")]), 6)
board.add(graph(
    "Server errors (5xx) per second",
    "Answers with status 500-599, per service. Should stay at 0.",
    # "or vector(0)": with no 5xx at all, the series does not exist and the
    # panel would say "No data", which looks broken. Show a flat 0 instead.
    PROMETHEUS, [('sum by (job) (rate(http_requests_total{statusCode=~"5.."}[1m])) or vector(0)', "{{job}}")]), 6)
board.add(graph(
    "Latency p95, backends",
    "95 of 100 requests were answered faster than this by the backend itself (5-minute window).",
    PROMETHEUS,
    [("histogram_quantile(0.95, sum by (le, job) (rate(http_request_duration_seconds_bucket[5m])))", "{{job}}")],
    unit="s"), 6)
board.add(graph(
    "Latency p95, at the Gateway",
    "95 of 100 requests for the app were answered faster than this, as the visitor sees it: "
    "the Gateway's time, including the backend.",
    LOKI,
    [(f"quantile_over_time(0.95, {GATEWAY} | unwrap duration | __error__=\"\" [5m]) by (host)", "app")],
    unit="s"), 6)

# ---------------------------------------------------------------- security
board.row("Security: who knocks, who is refused")
board.add(graph(
    "Failed logins per minute",
    "Wrong email or password: auth answered 401 on /api/auth/login.",
    PROMETHEUS,
    [('sum(increase(http_requests_total{job="auth", route="/api/auth/login", statusCode="401"}[1m]))',
      "failed logins")]), 8)
board.add(graph(
    "Login attempts at the Gateway, by answer",
    "Every POST to /api/auth/login from the internet. 401 = wrong password (answered by auth), "
    "429 = over the login limit (answered by the Gateway, auth never sees it), 200 = success.",
    LOKI,
    [(f'sum by (status) (count_over_time({GATEWAY} | path="/api/auth/login" [1m]))', "{{status}}")]), 8)
board.add(graph(
    "Refused tokens per minute",
    "Requests to a protected route with no token or a bad one (401 before any route), per service.",
    PROMETHEUS,
    [('sum by (job) (increase(http_requests_total{route="no_route", statusCode="401"}[1m]))', "{{job}}")]), 8)
board.add(graph(
    "Gateway answers per minute, by status",
    "Every request for the app from the internet. 403 = blocked path (user list), 429 = over a rate limit.",
    LOKI, [(f"sum by (status) (count_over_time({GATEWAY} [1m]))", "{{status}}")]), 8)
board.add({
    "type": "table", "title": "Top 10 client IPs, last 15 minutes",
    "description": "Requests for the app per client IP, and how many were refused (401, 403, 429).",
    "datasource": LOKI,
    "targets": [
        {"refId": "A", "datasource": LOKI, "queryType": "instant", "legendFormat": "{{ip}}",
         "expr": f"topk(10, sum by (ip) (count_over_time({GATEWAY} [15m])))"},
        {"refId": "B", "datasource": LOKI, "queryType": "instant", "legendFormat": "{{ip}}",
         "expr": f'sum by (ip) (count_over_time({GATEWAY} | status=~"401|403|429" [15m]))'},
    ],
    "transformations": [
        {"id": "merge", "options": {}},
        {"id": "organize", "options": {"excludeByName": {"Time": True},
                                       "renameByName": {"Value #A": "requests", "Value #B": "refused"}}},
        {"id": "sortBy", "options": {"sort": [{"field": "requests", "desc": True}]}},
    ],
    "fieldConfig": {"defaults": {}, "overrides": []}, "options": {"showHeader": True},
}, 16)
board.add({
    "type": "logs", "title": "Refused at the Gateway (401, 403, 429)",
    "description": "The newest refused requests for the app: status, IP, method, path.",
    "datasource": LOKI,
    "targets": [{"refId": "A", "datasource": LOKI,
                 "expr": f'{GATEWAY} | status=~"401|403|429" '
                         '| line_format "{{.status}}  {{.ip}}  {{.method}} {{.path}}"'}],
    "options": {"showTime": True, "wrapLogMessage": False, "sortOrder": "Descending"},
}, 24, 9)

# ---------------------------------------------------------------- health
board.row("Health")
board.add(number(
    "MongoDB connected",
    "Per backend: 1 = connected, 0 = lost (#28).",
    [("min by (job) (mongo_connection_status)", "{{job}}")],
    colors(("red", None), ("green", 1))), 6, 5)
board.add(number(
    "Restarts in restauranty, last hour",
    "Container restarts of the app's pods. A few after a cluster start are normal (#28).",
    [('sum(increase(kube_pod_container_status_restarts_total{namespace="restauranty"}[1h]))', "")],
    colors(("green", None), ("orange", 3), ("red", 10))), 6, 5)
board.add(number(
    "Series per scrape (F18 guard)",
    "How many series each backend sends to Prometheus. Above 1,000 Prometheus drops the scrape "
    "(sampleLimit). Junk URLs must not move this number.",
    [('max by (job) (scrape_samples_scraped{job=~"auth|discounts|items"})', "{{job}}")],
    colors(("green", None), ("orange", 700), ("red", 1000))), 6, 5)
board.add(number(
    "Users, items, coupons",
    "Counts from the database, refreshed every minute by the backends.",
    [("max(users_total)", "users"), ("max(items_total)", "items"), ("max(coupons_total)", "coupons")]), 6, 5)

# ---------------------------------------------------------------- write
dashboard = {
    "uid": "restauranty", "title": "Restauranty: traffic and security", "tags": ["restauranty"],
    "timezone": "browser", "schemaVersion": 41, "version": 1, "refresh": "30s",
    "time": {"from": "now-1h", "to": "now"}, "editable": True,
    "templating": {"list": []}, "annotations": {"list": []},
    "panels": board.panels,
}
body = json.dumps(dashboard, indent=2)
header = """\
# The Restauranty dashboard (#14), as code. GENERATED by scripts/build-dashboard.py:
# change that script, not this file. Grafana's dashboard loader reads every
# ConfigMap with the label grafana_dashboard in its namespace, so the dashboard
# comes back by itself after a rebuild.
apiVersion: v1
kind: ConfigMap
metadata:
  name: restauranty-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  restauranty.json: |
"""
out = Path(__file__).resolve().parent.parent / "k8s" / "monitoring" / "dashboard.yaml"
out.write_text(header + "\n".join("    " + line for line in body.splitlines()) + "\n")
print(f"wrote {out} ({len(board.panels)} panels)")
