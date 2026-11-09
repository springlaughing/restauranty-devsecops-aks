const express = require('express');
const router = express.Router();

const Campaigns = require('../models/campaigns.model')

// const fileUploader = require('./../config/cloudinary.config')

router.get("/", (req, res, next) => {

    Campaigns.find().then(campaigns => {
        res.json(campaigns)
    }).catch(err => {
        next(err)
    })

})

router.get("/:id", (req, res, next) => {

    const id = req.params.id

    Campaigns.findById(id).then(campaign => {
        res.json(campaign)
    }).catch(err => {
        next(err)
    })

})

router.post("/", (req, res, next) => {

    const campaign = req.body

    Campaigns.create(campaign)
        .then(newCampaign => {
            let id = newCampaign._id;
            return Campaigns.findByIdAndUpdate(
                id,
            );
        })
        .then(updatedCampaign => {
            res.json(updatedCampaign);
        })
        .catch(err => {
            next(err);
        });

})

router.put("/:id", (req, res, next) => {

    const campaign = req.body

    Campaigns.findByIdAndUpdate(campaign._id, campaign, { new: true }).then(newCampaign => {
        res.json(newCampaign)
    }).catch(err => {
        next(err)
    })
})

router.delete("/:id", (req, res, next) => {

    const id = req.params.id

    Campaigns.findByIdAndDelete(id).then(couponDeleted => {
        res.json({
            message: "Campaigns Eliminados",
            couponDeleted
        })
    }).catch(err => {
        next(err)
    })

})

module.exports = router;
