const jwt = require('jsonwebtoken');

const secret = process.env.JWT_SECRET || 'change-me';
const expiresIn = '1h';

function generateToken(payload) {
  return jwt.sign(payload, secret, { expiresIn });
}

function verifyToken(token) {
  return jwt.verify(token, secret);
}

module.exports = { generateToken, verifyToken };
