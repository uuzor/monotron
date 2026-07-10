/**
 * Wallet API routes
 * 
 * Endpoints (from monoton-wallet-invoice-lifecycle.md):
 * - GET /v1/wallet/balance - Get wallet balance (sum of Holdings)
 * 
 * NOTE: This module requires `npm run codegen` to generate TypeScript types
 * from the Daml DAR. The actual ledger operations are implemented after codegen.
 */

import { Router, Request, Response } from 'express';
import { logger } from '../index';

const router = Router();

// Extend Request type
declare global {
  namespace Express {
    interface Request {
      party?: string;
      token?: string;
    }
  }
}

/**
 * GET /v1/wallet/balance
 * Get wallet balance for the authenticated party
 */
router.get('/balance', async (req: Request, res: Response) => {
  try {
    const party = req.party;
    logger.info('Wallet balance query', { party });
    
    res.status(501).json({
      error: 'Not Implemented',
      message: 'Run `npm run codegen` to generate types from DAR.',
      party,
      balances: [],
      totalInstruments: 0,
    });
    
  } catch (error) {
    logger.error('Failed to get wallet balance', { error: (error as Error).message });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to get wallet balance',
    });
  }
});

/**
 * GET /v1/wallet/holdings
 * List individual holding contracts
 */
router.get('/holdings', async (req: Request, res: Response) => {
  try {
    const party = req.party;
    logger.info('Listing holdings', { party });
    
    res.status(501).json({
      error: 'Not Implemented',
      message: 'Run `npm run codegen` to generate types from DAR.',
      party,
      holdings: [],
      count: 0,
    });
    
  } catch (error) {
    logger.error('Failed to list holdings', { error: (error as Error).message });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to list holdings',
    });
  }
});

export { router as walletRoutes };
