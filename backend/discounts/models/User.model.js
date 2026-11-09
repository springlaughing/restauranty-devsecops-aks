const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true
  },
  surname: {
    type: String,
    required: true
  },  
  // Never loaded unless a query asks for it with .select('+password')
  // (only login does), so no route can return the hash by accident.
  password: {
    type: String,
    required: true,
    select: false
  },
  orderHistory: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Order'
  }],
  role: {
    type: String,
    default: 'admin'
  },
  email: {
    type: String,
    required: true
  },
  address: {
    type: String,
    required: true
  },
  paymentMethod: {
    type: String
  },
  phoneNumber: {
    type: String,
    required: true
  }
}, {
  // Second layer: even a document that was loaded with the password
  // (or a future query that forgets) never serializes it into a response.
  toJSON: {
    transform: (doc, ret) => {
      delete ret.password;
      return ret;
    }
  }
});

const User = mongoose.model('User', userSchema);

module.exports = User;