const express = require('express');
const router = express.Router();

const Coupons = require('../models/coupons.model')

// const fileUploader = require('./../config/cloudinary.config')

router.get("/", (req, res, next) => {

    Coupons.find().then(coupons => {
        res.json(coupons)
    }).catch(err => {
        next(err)
    })

})

router.get("/:id", (req, res, next) => {

    const id = req.params.id

    Coupons.findById(id).then(coupon => {
        res.json(coupon)
    }).catch(err => {
        next(err)
    })

})

router.post("/", (req, res, next) => {

    const coupon = req.body

    Coupons.create(coupon)
        .then(newCoupon => {
            let id = newCoupon._id;
            return Coupons.findByIdAndUpdate(
                id,
            );
        })
        .then(updatedCoupon => {
            res.json(updatedCoupon);
        })
        .catch(err => {
            next(err);
        });

})

router.put("/:id", (req, res, next) => {

    const coupon = req.body

    Coupons.findByIdAndUpdate(coupon._id, coupon, { new: true }).then(newCoupon => {
        res.json(newCoupon)
    }).catch(err => {
        next(err)
    })
})

router.delete("/:id", (req, res, next) => {

    const id = req.params.id

    Coupons.findByIdAndDelete(id).then(couponDeleted => {
        res.json({
            message: "Coupons Eliminados",
            couponDeleted
        })
    }).catch(err => {
        next(err)
    })

})

module.exports = router;
