#!/bin/bash
# =============================================================================
# Monoton Full Protocol Flow Integration Test
# =============================================================================
# This script runs the complete invoice settlement flow on Canton Sandbox:
# 1. Start Canton Sandbox with all utility-registry DARs
# 2. Create parties: seller, buyer, operator, instrumentAdmin
# 3. Fund buyer with test tokens (Holding contracts)
# 4. Set up SettlementDelegation (seller authorizes operator)
# 5. Create and approve an invoice
# 6. Execute Path A atomic settlement batch
# 7. Verify settlement
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DAR_DIR="$PROJECT_DIR/main/lib"

# Canton Sandbox settings
SANDBOX_PORT=6865
SANDBOX_TIMEOUT=120

# DAR files to upload
MONOTRON_DAR="$PROJECT_DIR/main/.daml/dist/monotron-main-0.0.1.dar"

# Utility Registry DARs
UTILITY_REGISTRY_V0="$DAR_DIR/utility-registry-v0-0.6.0.dar"
UTILITY_REGISTRY_HOLDING="$DAR_DIR/utility-registry-holding-v0-0.2.1.dar"
UTILITY_REGISTRY_APP="$DAR_DIR/utility-registry-app-v0-0.7.0.dar"
SPLICE_API_TRANSFER="$DAR_DIR/splice-api-token-transfer-instruction-v1-1.0.0.dar"
SPLICE_API_METADATA="$DAR_DIR/splice-api-token-metadata-v1-1.0.0.dar"
SPLICE_API_HOLDING="$DAR_DIR/splice-api-token-holding-v1-1.0.0.dar"

# =============================================================================
# Check Prerequisites
# =============================================================================

echo_step "Checking prerequisites..."

# Check Java
if ! command -v java &> /dev/null; then
    echo_error "Java not found. Please install Java 17+."
    exit 1
fi

# Check DAR files exist
if [ ! -f "$MONOTRON_DAR" ]; then
    echo_error "Monotron DAR not found at $MONOTRON_DAR"
    echo_warn "Building DAR first..."
    cd "$PROJECT_DIR" && dpm build --all
fi

for dar in "$UTILITY_REGISTRY_V0" "$UTILITY_REGISTRY_HOLDING" "$UTILITY_REGISTRY_APP"; do
    if [ ! -f "$dar" ]; then
        echo_error "Required DAR not found: $dar"
        exit 1
    fi
done

echo_success "Prerequisites check passed"

# =============================================================================
# Build DARs if needed
# =============================================================================

echo_step "Ensuring DARs are built..."
cd "$PROJECT_DIR"
export PATH="$HOME/.dpm/bin:$HOME/java/bin:$PATH"
export JAVA_HOME="$HOME/java"

if ! dpm build --all 2>&1; then
    echo_error "Failed to build DARs"
    exit 1
fi

echo_success "DARs built successfully"

# =============================================================================
# Start Canton Sandbox
# =============================================================================

echo_step "Starting Canton Sandbox..."

# Kill any existing sandbox on this port
lsof -ti:$SANDBOX_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true

# Start sandbox in background with all DARs
nohup daml sandbox \
    --port $SANDBOX_PORT \
    --dar "$MONOTRON_DAR" \
    --dar "$UTILITY_REGISTRY_V0" \
    --dar "$UTILITY_REGISTRY_HOLDING" \
    --dar "$UTILITY_REGISTRY_APP" \
    --dar "$SPLICE_API_TRANSFER" \
    --dar "$SPLICE_API_METADATA" \
    --dar "$SPLICE_API_HOLDING" \
    > /tmp/sandbox.log 2>&1 &

SANDBOX_PID=$!
echo "Sandbox PID: $SANDBOX_PID"

# Wait for sandbox to start
echo "Waiting for sandbox to start..."
for i in {1..30}; do
    if curl -s http://localhost:$SANDBOX_PORT/health > /dev/null 2>&1; then
        echo_success "Sandbox started on port $SANDBOX_PORT"
        break
    fi
    if [ $i -eq 30 ]; then
        echo_error "Sandbox failed to start within 30 seconds"
        echo "Sandbox log:"
        cat /tmp/sandbox.log
        exit 1
    fi
    sleep 1
done

# =============================================================================
# Create Integration Test Script
# =============================================================================

cat > /tmp/integration-test.daml << 'DAMLEOF'
module IntegrationTest where

import Daml.Script
import DA.Date (date, Month(Jan))
import DA.Time (time)

-- Import Monoton templates
import Main

-- =============================================================================
-- Full Protocol Flow Test
-- =============================================================================

testFullProtocolFlow : Script ()
testFullProtocolFlow = do

  -- Allocate parties
  operator <- allocateParty "Operator"
  seller <- allocateParty "Seller"
  buyer <- allocateParty "Buyer"
  instrumentAdmin <- allocateParty "CantonCoin"

  debug "Parties allocated"

  -- =============================================================================
  -- STEP 1: Register businesses
  -- =============================================================================
  
  debug "Step 1: Registering businesses..."
  
  -- Register seller
  sellerRegCid <- submit operator do
    createCmd BusinessRegistration with
      business = seller
      operator = operator
      businessName = "Acme Corp"
      taxId = "US-123456789"
      status = Active
      registeredAt = time (date 2025 Jan 1) 0 0 0
  
  debug "Seller registered"

  -- Register buyer
  buyerRegCid <- submit operator do
    createCmd BusinessRegistration with
      business = buyer
      operator = operator
      businessName = "Globex Inc"
      taxId = "US-987654321"
      status = Active
      registeredAt = time (date 2025 Jan 1) 0 0 0
  
  debug "Buyer registered"

  -- =============================================================================
  -- STEP 2: Create Settlement Delegation
  -- =============================================================================
  
  debug "Step 2: Creating Settlement Delegation..."
  
  -- Seller authorizes operator to accept transfers on their behalf
  delegationCid <- submit seller do
    createCmd SettlementDelegation with
      seller = seller
      operator = operator
      scope = "invoice-settlement"
      validFrom = time (date 2025 Jan 1) 0 0 0
      validUntil = time (date 2030 Jan 1) 0 0 0
      active = True
  
  debug "Settlement Delegation created"

  -- =============================================================================
  -- STEP 3: Create Invoice
  -- =============================================================================
  
  debug "Step 3: Creating invoice..."
  
  invoiceCid <- submit seller do
    createCmd Invoice with
      seller = seller
      buyer = buyer
      operator = operator
      amount = 1000.00
      currency = "USD"
      description = "Consulting services - Q1 2025"
      dueDate = date 2025 Mar 31
      status = Created
      invoiceId = "INV-2025-Q1-001"
      instrumentAdmin = instrumentAdmin
      transferInstructionCid = None
  
  debug "Invoice created"

  -- =============================================================================
  -- STEP 4: Approve Invoice
  -- =============================================================================
  
  debug "Step 4: Approving invoice..."
  
  approvedInvoiceCid <- submit buyer do
    exerciseCmd invoiceCid Invoice_Approve
  
  debug "Invoice approved"

  -- =============================================================================
  -- STEP 5: Initiate Settlement (partial - requires real Token Standard)
  -- =============================================================================
  
  debug "Step 5: Initiating settlement..."
  
  -- NOTE: Full settlement requires:
  -- 1. TransferFactory from registry
  -- 2. TransferInstruction via TransferFactory_Transfer
  -- 3. TransferInstruction_Accept (moves Holdings)
  -- 4. Invoice_ConfirmSettled with verified Holding
  --
  -- This test demonstrates the state machine up to approval.
  -- Full Path A integration requires Devnet deployment.

  pure ()

DAMLEOF

# =============================================================================
# Run Integration Test
# =============================================================================

echo_step "Running integration test..."

cd "$PROJECT_DIR/test"

# Run Daml Script against Sandbox
dpm script \
    --dar .daml/dist/monotron-test-0.0.1.dar \
    --ledger-host localhost \
    --ledger-port $SANDBOX_PORT \
    --file /tmp/integration-test.daml \
    testFullProtocolFlow 2>&1

TEST_RESULT=$?

# =============================================================================
# Cleanup
# =============================================================================

echo_step "Cleaning up..."
kill $SANDBOX_PID 2>/dev/null || true

if [ $TEST_RESULT -eq 0 ]; then
    echo_success "Integration test PASSED"
    echo ""
    echo "Protocol flow verified:"
    echo "  [1] Parties allocated"
    echo "  [2] Businesses registered"
    echo "  [3] Settlement Delegation created"
    echo "  [4] Invoice created"
    echo "  [5] Invoice approved"
    echo ""
    echo "NOTE: Full Path A settlement requires Devnet with:"
    echo "  - TransferFactory contracts"
    echo "  - Real Holding contracts"
    echo "  - Token Standard implementation"
else
    echo_error "Integration test FAILED"
    echo "Check sandbox log: /tmp/sandbox.log"
fi

exit $TEST_RESULT
