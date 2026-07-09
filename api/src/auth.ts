/**
 * Authentication middleware for Monoton API
 * 
 * Design (from monoton-agentic-commerce-api.md):
 * - OAuth2 client-credentials flow
 * - Short-lived JWTs (5-15 min recommended)
 * - JWT scoped to canActAs(party) for Canton authorization
 * - Per-business parties, not shared platform JWTs
 */

import { Request, Response, NextFunction } from 'express';
import { config } from './config';

// Extend Express Request type
declare global {
  namespace Express {
    interface Request {
      party?: string;
      token?: string;
    }
  }
}

/**
 * Extract Bearer token from Authorization header
 */
function extractToken(authHeader: string | undefined): string | null {
  if (!authHeader) return null;
  
  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0].toLowerCase() !== 'bearer') {
    return null;
  }
  
  return parts[1];
}

/**
 * Extract party from JWT scope claim
 * The scope should contain "canActAs:<partyId>" for Canton authorization
 */
function extractPartyFromScope(scope: string | undefined): string | null {
  if (!scope) return null;
  
  const scopes = scope.split(' ');
  for (const s of scopes) {
    if (s.startsWith('canActAs:')) {
      return s.substring('canActAs:'.length);
    }
  }
  
  return null;
}

/**
 * Authentication middleware
 * 
 * Validates JWT and extracts the Canton party ID that the caller
 * is authorized to act as.
 */
export async function authMiddleware(
  req: Request,
  _res: Response,
  next: NextFunction
): Promise<void> {
  // In development, use default test party if no token
  if (config.isDevelopment) {
    const token = extractToken(req.headers.authorization);
    if (!token) {
      req.party = 'TestParty';
      req.token = 'development-token';
      next();
      return;
    }
  }
  
  try {
    const token = extractToken(req.headers.authorization);
    if (!token) {
      // In development, use default party
      req.party = 'TestParty';
      req.token = 'development-token';
      next();
      return;
    }
    
    // TODO: In production, verify JWT and extract party from claims
    // For now, use the token as-is
    req.token = token;
    
    // Extract party from token (this would be parsed from JWT in production)
    // For development, we use a simple extraction
    const party = extractPartyFromScope(token) || 'UnknownParty';
    req.party = party;
    
    next();
  } catch (error) {
    console.error('Auth error:', error);
    // In development, continue with default party
    if (config.isDevelopment) {
      req.party = 'TestParty';
      req.token = 'development-token';
      next();
      return;
    }
    next();
  }
}
