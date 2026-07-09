/**
 * Health check routes
 */

import { Router, Request, Response } from 'express';

const router = Router();

interface HealthStatus {
  status: 'healthy' | 'unhealthy';
  timestamp: string;
  version: string;
}

/**
 * GET /health
 * Basic health check
 */
router.get('/', (_req: Request, res: Response) => {
  const status: HealthStatus = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '0.0.1',
  };
  res.json(status);
});

/**
 * GET /health/live
 * Liveness check - just confirms the process is running
 */
router.get('/live', (_req: Request, res: Response) => {
  res.json({
    status: 'alive',
    timestamp: new Date().toISOString(),
  });
});

export { router as healthRoutes };
