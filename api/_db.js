const { Pool } = require('@neondatabase/serverless');

function getPool() {
  if (!process.env.DATABASE_URL) {
    return null;
  }
  return new Pool({ connectionString: process.env.DATABASE_URL });
}

module.exports = { getPool };
