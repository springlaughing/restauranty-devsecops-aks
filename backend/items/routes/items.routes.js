const express = require('express');
const router = express.Router();

const Item = require('../models/Item.model')


const fileUploader = require('../config/cloudinary.config')

router.get("/", (req, res, next) => {

    Item.find().then(items => {
        res.json(items)
    }).catch(err => {
        next(err)
    })

})

router.get("/:id", (req, res, next) => {

    const id = req.params.id

    Item.findById(id).then(items => {
        res.json(items)
    }).catch(err => {
        next(err)
    })

})

router.post("/", fileUploader.single("imagem"), (req, res, next) => {

    const item = req.body

    const data = req.file.path

    Item.create(item)
        .then(newItem => {
            let id = newItem._id;
            return Item.findByIdAndUpdate(
                id,
                { $push: { image: data } }
            );
        })
        .then(updatedItem => {
            res.json(updatedItem);
        })
        .catch(err => {
            next(err);
        });

})

router.put("/:id", fileUploader.single("imagem"), (req, res, next) => {
    const itemId = req.params.id;
    const item = req.body;

    if (req.file) {
        // New file is uploaded, process and update the image URL
        const imagePath = req.file.path;
        item.image = [imagePath]; // Assign the updated image path to the image array
    }

    Item.findByIdAndUpdate(itemId, item, { new: true })
        .then(updatedItem => {
            res.json(updatedItem);
        })
        .catch(err => {
            next(err);
        });
});



router.delete("/:id", (req, res, next) => {

    const id = req.params.id

    Item.findByIdAndDelete(id).then(itemDeleted => {
        res.json({
            message: "Item Eliminado",
            itemDeleted
        })
    }).catch(err => {
        next(err)
    })

})

module.exports = router;
