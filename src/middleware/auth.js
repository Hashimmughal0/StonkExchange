const pool = require('../config/db');
const { verifyToken } = require('../utils/jwt');

async function authenticate(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Missing auth token' });
  }

  const token = header.split(' ')[1];
  try {
    const payload = verifyToken(token);
    const session = await pool.query(
      'SELECT user_id FROM sessions WHERE token = $1 AND expires_at > NOW()',
      [token]
    );

    if (!session.rows.length) {
      return res.status(401).json({ message: 'Session expired' });
    }

    req.user = {
      userId: payload.userId,
      role: payload.role,
      token
    };

    next();
  } catch (err) {
    return res.status(401).json({ message: 'Invalid token' });
  }
}

function requireAdmin(req, res, next) {
  if (!req.user || req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Admin role required' });
  }
  next();
}

module.exports = { authenticate, requireAdmin };
