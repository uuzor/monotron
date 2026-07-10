/**
 * Invoice API routes
 * 
 * Endpoints (from monoton-agentic-commerce-api.md):
 * - POST /v1/invoices          - Create invoice (caller is seller)
 * - GET  /v1/invoices/:id      - Get invoice details
 * - POST /v1/invoices/:id/approve - Approve invoice (caller is buyer)
 * - POST /v1/invoices/:id/settle  - Settle invoice (Path A batch)
 * 
 * NOTE: This module requires `npm run codegen` to generate TypeScript types
 * from the Daml DAR. The actual ledger operations are implemented after codegen.
 */

import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { logger } from '../index';

// Validation schemas
const createInvoiceSchema = z.object({
  buyer: z.string().min(1),
  amount: z.number().positive(),
  currency: z.string().length(2).default('CC'),
  description: z.string().min(1).max(500),
  dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  metadata: z.record(z.string()).optional(),
});

const settleInvoiceSchema = z.object({
  autoMerge: z.boolean().default(true),
});

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
 * POST /v1/invoices
 * Create a new invoice
 */
router.post('/', async (req: Request, res: Response) => {
  try {
    const party = req.party;
    
    const validation = createInvoiceSchema.safeParse(req.body);
    if (!validation.success) {
      res.status(400).json({
        error: 'Bad Request',
        details: validation.error.issues,
      });
      return;
    }
    
    const data = validation.data;
    const invoiceId = `INV-${Date.now()}-${Math.random().toString(36).substring(2, 10).toUpperCase()}`;
    
    logger.info('Creating invoice', { invoiceId, seller: party, buyer: data.buyer });
    
    res.status(501).json({
      error: 'Not Implemented',
      message: 'Run `npm run codegen` to generate types from DAR, then implement ledger operations.',
      _placeholder: {
        invoiceId,
        seller: party,
        buyer: data.buyer,
        amount: data.amount,
        currency: data.currency,
        status: 'Created',
      }
    });
    
  } catch (error) {
    logger.error('Failed to create invoice', { error: (error as Error).message });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to create invoice',
    });
  }
});

/**
 * GET /v1/invoices/:id
 * Get invoice details
 */
router.get('/:id', async (req: Request, res: Response) => {
  try {
    const invoiceId = req.params.id;
    logger.info('Getting invoice', { invoiceId });
    
    res.status(501).json({
      error: 'Not Implemented',
      message: 'Run `npm run codegen` to generate types from DAR.',
      invoiceId,
    });
    
  } catch (error) {
    logger.error('Failed to get invoice', { error: (error as Error).message });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to get invoice',
    });
  }
});

/**
 * POST /v1/invoices/:id/approve
 * Approve an invoice (buyer only)
 */
router.post('/:id/approve', async (req: Request, res: Response) => {
  try {
    const party = req.party;
    const invoiceId = req.params.id;
    logger.info('Approving invoice', { invoiceId, buyer: party });
    
    res.status(501).json({
      error: 'Not Implemented',
      message: 'Run `npm run codegen` to generate types from DAR.',
      invoiceId,
      status: 'Approved',
    });
    
  } catch (error) {
    logger.error('Failed to approve invoice', { error: (error as Error).message });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to approve invoice',
    });
  }
});

/**
 * POST /v1/invoices/:id/settle
 * Settle an invoice using Path A atomic batch
 */
router.post('/:id/settle', async (req: Request, res: Response) => {
  try {
    const party = req.party;
    const invoiceId = req.params.id;
    
    const validation = settleInvoiceSchema.safeParse(req.body || {});
    if (!validation.success) {
      res.status(400).json({
        error: 'Bad Request',
        details: validation.error.issues,
      });
      return;
    }
    
    logger.info('Settling invoice (Path A)', { invoiceId, party });
    
    res.status(501).json({
      error: 'Not Implemented',
      message: 'Run `npm run codegen` to generate types from DAR.',
      invoiceId,
      status: 'Settled',
      path: 'A',
    });
    
  } catch (error) {
    logger.error('Failed to settle invoice', { error: (error as Error).message });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to settle invoice',
    });
  }
});

/**
 * GET /v1/invoices
 * List all invoices for the authenticated party
 */
router.get('/', async (req: Request, res: Response) => {
  try {
    const party = req.party;
    logger.info('Listing invoices', { party });
    
    res.status(501).json({
      error: 'Not Implemented',
      message: 'Run `npm run codegen` to generate types from DAR.',
      invoices: [],
      count: 0,
    });
    
  } catch (error) {
    logger.error('Failed to list invoices', { error: (error as Error).message });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to list invoices',
    });
  }
});

export { router as invoiceRoutes };
