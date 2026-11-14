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


def graph(title, description, source, queries, unit="short", no_value=None):
    """A time series panel. queries: list of (query, legend).
    no_value: text to show when the query finds nothing (instead of "No data")."""
    defaults = {"unit": unit, "min": 0}
    if no_value is not None:
        defaults["noValue"] = no_value
    return {
        "type": "timeseries", "title": title, "description": description,
        "datasource": source,
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {"legend": {"showLegend": True, "displayMode": "list", "placement": "bottom"},
                    "tooltip": {"mode": "multi"}},
        "targets": [{"refId": chr(65 + i), "expr": q, "legendFormat": legend, "datasource": source}
                    for i, (q, legend) in enumerate(queries)],
    }


def number(title, description, queries, steps=None, unit=None, no_value=None, instant=False, mappings=None):
    """A stat panel: the latest value, big. queries: list of (query, legend).
    no_value: text to show when the query finds nothing (instead of "No data").
    instant: ask for the value at this moment only. Without it, the panel
    queries the whole time range and shows the last value that is not empty,
    which can be an hour old when the data has stopped (build log, entry 66).
    mappings: Grafana value mappings, to show a word instead of a number."""
    steps = steps or [{"color": "text", "value": None}]
    defaults = {"thresholds": {"mode": "absolute", "steps": steps}}
    if unit:
        defaults.update({"unit": unit, "decimals": 0})
    if no_value is not None:
        defaults["noValue"] = no_value
    if mappings:
        defaults["mappings"] = mappings
    return {
        "type": "stat", "title": title, "description": description, "datasource": PROMETHEUS,
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "value", "graphMode": "none", "textMode": "auto"},
        "targets": [{"refId": chr(65 + i), "expr": q, "legendFormat": legend, "datasource": PROMETHEUS,
                     **({"instant": True, "range": False} if instant else {})}
                    for i, (q, legend) in enumerate(queries)],
    }


def log_count(title, description, query, steps):
    """A stat panel from Loki: how many log lines match, in the dashboard's time range."""
    return {
        "type": "stat", "title": title, "description": description, "datasource": LOKI,
        "fieldConfig": {"defaults": {"noValue": "0", "thresholds": {"mode": "absolute", "steps": steps}},
                        "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "value", "graphMode": "none", "textMode": "auto"},
        "targets": [{"refId": "A", "datasource": LOKI, "queryType": "instant", "expr": query}],
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
    PROMETHEUS, [("sum by (job) (rate(http_requests_total[1m]))", "{{job}}")]), 8)
board.add(graph(
    "Server errors from the backends (5xx)",
    "Answers with status 500-599 that a backend gave itself, per service and per second. Should stay at 0.",
    # "or vector(0)": with no 5xx at all, the series does not exist and the
    # panel would say "No data", which looks broken. Show a flat 0 instead.
    PROMETHEUS, [('sum by (job) (rate(http_requests_total{statusCode=~"5.."}[1m])) or vector(0)', "{{job}}")]), 8)
board.add(graph(
    "Server errors at the Gateway (502, 503, 504)",
    "Answers with status 500-599 that the Gateway gave for the app. 502/503/504 mean the Gateway could "
    "not reach a backend: pods gone, crashed, or a network rule in the way. The backends' own metrics "
    "never see these, because the requests do not arrive. Should stay at 0.",
    LOKI, [(f'sum by (status) (count_over_time({GATEWAY} | status=~"5.." [1m]))', "{{status}}")],
    no_value="0"), 8)
board.add(graph(
    "Latency p95, backends",
    "95 of 100 requests were answered faster than this by the backend itself (5-minute window).",
    PROMETHEUS,
    [("histogram_quantile(0.95, sum by (le, job) (rate(http_request_duration_seconds_bucket[5m])))", "{{job}}")],
    unit="s"), 12)
board.add(graph(
    "Latency p95, at the Gateway",
    "95 of 100 requests for the app were answered faster than this, as the visitor sees it: "
    "the Gateway's time, including the backend.",
    LOKI,
    [(f"quantile_over_time(0.95, {GATEWAY} | unwrap duration | __error__=\"\" [5m]) by (host)", "app")],
    unit="s"), 12)

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
board.add(log_count(
    "Day-one leak: requests for the user list",
    "Requests for /api/auth/users that the Gateway refused (403), in the dashboard's time range. Before "
    "the fixes, this path gave every user's password hash to anyone (finding F11). Nobody legitimate asks "
    "for it now, so every request here is someone probing. Any spelling counts: the block ignores case.",
    f'sum(count_over_time({GATEWAY} | path=~"(?i)/api/auth/users.*" | status="403" [$__range]))',
    colors(("green", None), ("red", 1))), 6)
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
}, 10)
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

# ---------------------------------------------------------------- images
# From the Trivy Operator (k8s/monitoring/trivy-operator-values.yaml): one
# number per running image and severity. "max by" because both copies of a
# backend run the same image and share one report.
TRIVY = 'trivy_image_vulnerabilities{namespace="restauranty"%s}'

# Scan coverage (#61, build log entry 66): what runs, against what has a
# report. The same comparison as the alert RestaurantyImageNotScanned in
# k8s/monitoring/alert-rules.yaml: a workload with ready pods and no Trivy
# series of its own. A clean report still gives a series (value 0), so
# "clean" and "never scanned" differ.
RUNNING = ('(count(kube_replicaset_status_ready_replicas{namespace="restauranty"} > 0) or vector(0))'
           ' + (count(kube_statefulset_status_replicas_ready{namespace="restauranty"} > 0) or vector(0))')
NOT_SCANNED = (
    '((kube_replicaset_status_ready_replicas{namespace="restauranty"} > 0)'
    ' unless on (namespace, replicaset) label_replace('
    + TRIVY % ', resource_kind="ReplicaSet", severity="Critical"'
    + ', "replicaset", "$1", "resource_name", "(.*)"))'
    ' or ((kube_statefulset_status_replicas_ready{namespace="restauranty"} > 0)'
    ' unless on (namespace, statefulset) label_replace('
    + TRIVY % ', resource_kind="StatefulSet", severity="Critical"'
    + ', "statefulset", "$1", "resource_name", "(.*)"))'
)
board.row("Vulnerabilities in running images (Trivy Operator)")
board.add(number(
    "Scan coverage",
    "How many of the running images have a scan result. Below 100%, some images run without a scan. "
    "0% means the scanner sends nothing at all. After a deploy, a new image needs a few minutes. "
    "Alerts: RestaurantyImageNotScanned, RestaurantyScanJobFailed.",
    [(f'100 * (({RUNNING}) - (count({NOT_SCANNED}) or vector(0))) / ({RUNNING})', "")],
    colors(("red", None), ("green", 100)), unit="percent", instant=True), 4, 8)
# No "or vector(0)" in the two panels below (build log, entry 66): with the
# scanner stopped, that fallback turned "nothing is known" into a green 0, a
# false all-clear. A clean image still has a series with the value 0, so the
# sum is a real 0 when scans exist, and "no scan data" when none do.
# Colors: neutral below 0, so "no scan data" is not painted green (Grafana
# colors the no-value text with the lowest step); green from 0.
board.add(number(
    "CRITICAL in running images",
    "CRITICAL vulnerabilities in the images that run now. The pipeline already blocks CRITICAL before "
    "a deploy. This panel catches the rest: new CVEs found after a deploy, and MongoDB, which the "
    "pipeline does not build. Alert: RestaurantyCriticalVulnerability."
    "\n\n\"no scan data\": the scanner sends nothing right now. That does not mean clean. It means unknown. Check Scan coverage.",
    [('sum(max by (image_repository) (' + TRIVY % ', severity="Critical"' + '))', "")],
    colors(("text", None), ("green", 0), ("red", 1)), no_value="no scan data", instant=True), 4, 8)
board.add(number(
    "Images with HIGH",
    "How many running images have at least one HIGH vulnerability."
    "\n\n\"no scan data\": the scanner sends nothing right now. That does not mean clean. It means unknown. Check Scan coverage.",
    [('count(max by (image_repository) (' + TRIVY % ', severity="High"' + ') > 0)'
      ' or (0 * count(max by (image_repository) (' + TRIVY % ', severity="High"' + ')))', "")],
    colors(("text", None), ("green", 0), ("orange", 1)), no_value="no scan data", instant=True), 4, 8)
board.add({
    "type": "table", "title": "Per image",
    "description": "Known vulnerabilities per running image, by severity. Details per CVE: "
                   "kubectl describe vulnerabilityreport -n restauranty <name>\n\n"
                   "Empty: the scanner sends nothing right now, see Scan coverage.",
    "datasource": PROMETHEUS,
    "targets": [
        {"refId": s_, "datasource": PROMETHEUS, "instant": True, "format": "table", "legendFormat": "{{image_repository}}",
         "expr": 'max by (image_repository) (' + TRIVY % (', severity="%s"' % sev) + ')'}
        for s_, sev in (("A", "Critical"), ("B", "High"), ("C", "Medium"))
    ],
    "transformations": [
        {"id": "merge", "options": {}},
        {"id": "organize", "options": {"excludeByName": {"Time": True},
                                       "renameByName": {"image_repository": "image", "Value #A": "critical",
                                                        "Value #B": "high", "Value #C": "medium"}}},
        {"id": "sortBy", "options": {"sort": [{"field": "critical", "desc": True}]}},
    ],
    "fieldConfig": {"defaults": {}, "overrides": []}, "options": {"showHeader": True},
}, 12, 8)

# ---------------------------------------------------------- scanner health
# Scan coverage says THAT something is wrong; these three say WHAT (#61, build
# log entry 66). None of them needs the scanner to be alive: they come from
# kube-state-metrics, and from the comparison behind the alert.
board.row("Scanner health (scans at each deploy and every 24 h)")
board.add(number(
    "Scanner",
    "On: the scanner is switched on and ready to start scans. It does not mean a scan is running "
    "right now: each scan is a short job of about 30 seconds. This comes from Kubernetes, so it "
    "still answers when the scanner is gone.\n\n"
    "How often scans run: each new image within a few minutes of starting (2 scans at a time, about "
    "5 minutes between rounds), and every image again every 24 hours, with that day's list of known "
    "vulnerabilities.\n\n"
    "When each image was last scanned (the AGE column): kubectl get vulnerabilityreports -n restauranty\n\n"
    "The settings (SCANNER_REPORT_TTL = rescan interval, CONCURRENT_SCAN_JOBS_LIMIT = scans at a "
    "time): kubectl get configmap trivy-operator-config -n trivy-system -o yaml | grep -iE \"ttl|concurrent\"",
    [('kube_deployment_status_replicas_available{namespace="trivy-system", deployment="trivy-operator"}', "")],
    colors(("red", None), ("green", 1)), no_value="unknown", instant=True,
    mappings=[{"type": "value", "options": {"0": {"text": "off", "color": "red", "index": 0}}},
              {"type": "range", "options": {"from": 1, "to": 100,
                                            "result": {"text": "on", "color": "green", "index": 1}}}]), 4, 8)
board.add(number(
    "Failed scan jobs",
    "Scan jobs that failed, for example because their node had no CPU left. Failed jobs are deleted "
    "after 10 minutes, so this counts recent failures only. The reason: "
    "kubectl get events -n trivy-system --sort-by=.lastTimestamp",
    [('sum(kube_job_status_failed{namespace="trivy-system"}) or vector(0)', "")],
    colors(("green", None), ("red", 1)), instant=True), 4, 8)
# One name column for both kinds of workload: label_replace copies the
# replicaset or the statefulset label into "workload".
NOT_SCANNED_NAMES = ('label_replace(label_replace(' + NOT_SCANNED + ', "workload", "$1", "replicaset", "(.+)"),'
                     ' "workload", "$1", "statefulset", "(.+)")')
board.add({
    "type": "table", "title": "Running without a scan",
    "description": "Workloads that run now and have no scan result: the same list as the alert "
                   "RestaurantyImageNotScanned, which fires when one stays here for 30 minutes. "
                   "Empty is good.",
    "datasource": PROMETHEUS,
    "targets": [{"refId": "A", "datasource": PROMETHEUS, "instant": True, "format": "table",
                 "expr": NOT_SCANNED_NAMES}],
    "transformations": [{"id": "organize", "options": {
        "indexByName": {"workload": 0},
        "excludeByName": {"Time": True, "Value": True, "__name__": True, "container": True, "endpoint": True,
                          "instance": True, "job": True, "namespace": True, "pod": True, "service": True,
                          "replicaset": True, "statefulset": True, "uid": True}}}],
    "fieldConfig": {"defaults": {"noValue": "none: every running image has a scan result"}, "overrides": []},
    "options": {"showHeader": True},
}, 16, 8)

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
