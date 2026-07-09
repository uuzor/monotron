/**
 * Configuration for Monoton Agentic Commerce API
 * 
 * Environment variables:
 * - LEDGER_HOST: Daml ledger host (default: localhost)
 * - LEDGER_PORT: Daml ledger port (default: 6865)
 * - LEDGER_TLS: Use TLS (default: false)
 * - AUTH_ISSUER: OAuth2/JWT issuer URL
 * - AUTH_AUDIENCE: Expected JWT audience
 * - CORS_ORIGIN: CORS allowed origin
 * - PORT: Server port (default: 3000)
 * - LOG_LEVEL: Winston log level (default: info)
 * - ENVIRONMENT: deployment environment (development/staging/production)
 */

import dotenv from 'dotenv';

// Load .env file in development
if (process.env.NODE_ENV !== 'production') {
  dotenv.config();
}

const env = {
  ledgerHost: process.env.LEDGER_HOST || 'localhost',
  ledgerPort: parseInt(process.env.LEDGER_PORT || '6865', 10),
  ledgerTls: process.env.LEDGER_TLS === 'true',
  
  authIssuer: process.env.AUTH_ISSUER || 'https://auth.example.com',
  authAudience: process.env.AUTH_AUDIENCE || 'monoton-api',
  
  corsOrigin: process.env.CORS_ORIGIN || '*',
  port: parseInt(process.env.PORT || '3000', 10),
  logLevel: process.env.LOG_LEVEL || 'info',
  environment: process.env.ENVIRONMENT || 'development',
  
  // DAR file path for type generation
  darPath: process.env.DAR_PATH || '../main/.daml/dist/monotron-main-0.0.1.dar',
};

export const config = {
  ...env,
  isDevelopment: env.environment === 'development',
  isProduction: env.environment === 'production',
};

// Validate required configuration
export function validateConfig(): void {
  const errors: string[] = [];
  
  if (!env.ledgerHost) errors.push('LEDGER_HOST is required');
  if (isNaN(env.ledgerPort)) errors.push('LEDGER_PORT must be a number');
  if (!env.authIssuer) errors.push('AUTH_ISSUER is required');
  
  if (errors.length > 0) {
    throw new Error(`Configuration errors: ${errors.join(', ')}`);
  }
}

// Validate on module load
try {
  validateConfig();
} catch (e) {
  if (config.isDevelopment) {
    console.warn('Configuration warning:', (e as Error).message);
  }
}
