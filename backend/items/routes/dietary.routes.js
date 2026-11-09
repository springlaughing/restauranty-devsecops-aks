const express = require('express');
const router = express.Router();

const Dietary = require('../models/dietary.model')

const fileUploader = require('../config/cloudinary.config')

router.get("/", (req, res, next) => {

    Dietary.find().then(dietary => {
        res.json(dietary)
    }).catch(err => {
        next(err)
    })

})

router.get("/:id", (req, res, next) => {

    const id = req.params.id

    Dietary.findById(id).then(dietary => {
        res.json(dietary)
    }).catch(err => {
        next(err)
    })

})

router.post("/", fileUploader.single("imagem"), (req, res, next) => {

    const dietary = req.body

    console.log(dietary)
    console.log(5)

    Dietary.create(dietary)
        .then(newDietary => {
            console.log(newDietary)
            let id = newDietary._id;
            return Dietary.findByIdAndUpdate(
                id,
            );
        })
        .then(updatedItem => {
            res.json(updatedItem);
        })
        .catch(err => {
            next(err);
        });

})

router.put("/:id", (req, res, next) => {

    const dietary = req.body

    Dietary.findByIdAndUpdate(dietary._id, dietary, { new: true }).then(newDietary => {
        res.json(newDietary)
    }).catch(err => {
        next(err)
    })
})

router.delete("/:id", (req, res, next) => {

    const id = req.params.id

    Dietary.findByIdAndDelete(id).then(dietaryDeleted => {
        res.json({
            message: "Dietary Eliminados",
            dietaryDeleted
        })
    }).catch(err => {
        next(err)
    })

})

module.exports = router;
