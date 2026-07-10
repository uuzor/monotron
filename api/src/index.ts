/**
 * Monoton Agentic Commerce REST API
 * 
 * A thin REST service in front of the Daml Ledger API for B2B invoice settlement.
 * This API enables AI agents and SaaS platforms to create, approve, and settle
 * invoices programmatically on Canton.
 * 
 * Key design decisions (from monoton-agentic-commerce-api.md):
 * - JSON Ledger API for HTTP/JSON interoperability
 * - OAuth2 client-credentials for authentication
 * - Per-business Canton parties with scoped JWTs
 * - Path A settlement: atomic batch transaction
 * 
 * NOTE: This API requires `npm run codegen` to generate TypeScript types from
 * the Daml DAR before it can be fully functional. Run `npm run codegen` first.
 */

import express, { Express, Request, Response, NextFunction } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import winston from 'winston';
import { config } from './config';
import { authMiddleware } from './auth';
import { invoiceRoutes } from './routes/invoices';
import { walletRoutes } from './routes/wallet';
import { healthRoutes } from './routes/health';

// Configure logging
const logger = winston.createLogger({
  level: config.logLevel,
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    })
  ]
});

// Create Express app
const app: Express = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: config.corsOrigin,
  credentials: true
}));

// Parse JSON bodies
app.use(express.json());

// Request logging
app.use((req: Request, _res: Response, next: NextFunction) => {
  logger.info(`${req.method} ${req.path}`, {
    ip: req.ip,
    userAgent: req.get('User-Agent')
  });
  next();
});

// Health check routes (no auth)
app.use('/health', healthRoutes);

// Authentication middleware for all other routes
app.use(authMiddleware);

// API routes
app.use('/v1/invoices', invoiceRoutes);
app.use('/v1/wallet', walletRoutes);

// Error handling
app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  logger.error('Unhandled error', { error: err.message, stack: err.stack });
  res.status(500).json({
    error: 'Internal Server Error',
    message: config.isDevelopment ? err.message : undefined
  });
});

// 404 handler
app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: 'Not Found' });
});

// Start server
const PORT = config.port;

app.listen(PORT, () => {
  logger.info(`Monoton API server starting`, {
    port: PORT,
    ledgerHost: config.ledgerHost,
    ledgerPort: config.ledgerPort,
    environment: config.environment
  });
  logger.info('API endpoints:');
  logger.info('  GET  /health');
  logger.info('  POST /v1/invoices          - Create invoice');
  logger.info('  GET  /v1/invoices/:id      - Get invoice');
  logger.info('  POST /v1/invoices/:id/approve - Approve invoice');
  logger.info('  POST /v1/invoices/:id/settle  - Settle invoice (Path A)');
  logger.info('  GET  /v1/wallet/balance     - Get wallet balance');
});

export { app, logger };
