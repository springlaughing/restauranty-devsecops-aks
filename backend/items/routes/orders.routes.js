const express = require('express');
const router = express.Router();

const Order = require('../models/Order.model')

// const fileUploader = require('./../config/cloudinary.config')

router.get("/", (req, res, next) => {

    Order.find().then(orders => {
        console.log(orders);
        res.json(orders)
    }).catch(err => {
        next(err)
    })

})

router.get("/:id", (req, res, next) => {

    const id = req.params.id

    Order.findById(id).then(order => {
        res.json(order)
    }).catch(err => {
        next(err)
    })

})

router.put("/", (req, res, next) => {

    const order = req.body

    order.findByIdAndUpdate(order._id, order, { new: true }).then(newOrder => {
        res.json(newOrder)
    }).catch(err => {
        next(err)
    })

})

router.delete("/:id", (req, res, next) => {

    const id = req.params.id

    Order.findByIdAndDelete(id).then(orderDeleted => {
        res.json({
            message: "Order Eliminado",
            orderDeleted
        })
    }).catch(err => {
        next(err)
    })

})

module.exports = router;
