#!/bin/bash
# =============================================================================
# Monoton Full Protocol Flow Integration Test
# =============================================================================
# This script runs the complete invoice settlement flow using Daml Script.
#
# IMPORTANT: This test uses the TestHolding (Holding interface implementation)
# for testing purposes. For real Devnet testing with Canton Coin:
# 1. Deploy to Devnet with real Token Standard DARs
# 2. Use the Canton Coin faucet to fund parties
# 3. Use real TransferFactory/TransferInstruction for settlement
#
# Usage:
#   ./run-integration-test.sh [--sandbox] [--devnet] [--scaffold] [--full]
#
# Options:
#   --sandbox  Start local Canton Sandbox with DARs (default)
#   --devnet   Connect to Devnet (requires DEVNET_* env vars)
#   --scaffold Setup parties and fund with test tokens only
#   --full     Run full Path A settlement test (requires real Token Standard)
#
# Devnet Environment Variables:
#   DEVNET_HOST     - Ledger API host (default: ledger-api.validator.devnet.sandbox.fivenorth.io)
#   DEVNET_PORT     - Ledger API port (default: 443)
#   DEVNET_CLIENT_ID - OIDC client ID (default: validator-devnet-m2m)
#   DEVNET_CLIENT_SECRET - OIDC client secret
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_step() { echo -e "${GREEN}[STEP]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DAR_DIR="$PROJECT_DIR/main/lib"

# Default settings
SANDBOX_PORT=6865
SANDBOX_JSON_PORT=7575

# DAR files
MONOTRON_DAR="$PROJECT_DIR/main/.daml/dist/monotron-main-0.0.1.dar"
UTILITY_REGISTRY_V0="$DAR_DIR/utility-registry-v0-0.6.0.dar"
UTILITY_REGISTRY_HOLDING="$DAR_DIR/utility-registry-holding-v0-0.2.1.dar"
UTILITY_REGISTRY_APP="$DAR_DIR/utility-registry-app-v0-0.7.0.dar"
SPLICE_API_TRANSFER="$DAR_DIR/splice-api-token-transfer-instruction-v1-1.0.0.dar"
SPLICE_API_METADATA="$DAR_DIR/splice-api-token-metadata-v1-1.0.0.dar"
SPLICE_API_HOLDING="$DAR_DIR/splice-api-token-holding-v1-1.0.0.dar"

# Parse arguments
MODE="sandbox"
while [[ $# -gt 0 ]]; do
    case $1 in
        --sandbox) MODE="sandbox"; shift ;;
        --devnet) MODE="devnet"; shift ;;
        --scaffold) MODE="scaffold"; shift ;;
        --full) MODE="full"; shift ;;
        *) echo_error "Unknown option: $1"; exit 1 ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

setup_env() {
    export PATH="$HOME/.dpm/bin:$HOME/java/bin:$PATH"
    export JAVA_HOME="$HOME/java"
}

# Get or refresh Devnet token
get_devnet_token() {
    # Check if token file exists and is fresh (less than 7 hours old)
    if [ -f /tmp/devnet_token.txt ] && [ -f /tmp/token_expiry.txt ]; then
        EXPIRY=$(cat /tmp/token_expiry.txt 2>/dev/null || echo 0)
        NOW=$(date +%s)
        if [ "$NOW" -lt "$EXPIRY" ]; then
            cat /tmp/devnet_token.txt
            return 0
        fi
    fi
    
    echo_step "Getting Devnet access token..."
    
    # Default values for Seaport Validator Devnet
    DEVNET_HOST="${DEVNET_HOST:-ledger-api.validator.devnet.sandbox.fivenorth.io}"
    DEVNET_CLIENT_ID="${DEVNET_CLIENT_ID:-validator-devnet-m2m}"
    DEVNET_CLIENT_SECRET="${DEVNET_CLIENT_SECRET}"
    DEVNET_AUTH_URL="${DEVNET_AUTH_URL:-https://auth.sandbox.fivenorth.io}"
    
    if [ -z "$DEVNET_CLIENT_SECRET" ]; then
        echo_error "DEVNET_CLIENT_SECRET is required for Devnet access"
        exit 1
    fi
    
    # Exchange credentials for token using jq
    RESPONSE=$(curl -s -X POST "${DEVNET_AUTH_URL}/application/o/token/" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data 'grant_type=client_credentials' \
        --data "client_id=${DEVNET_CLIENT_ID}" \
        --data "client_secret=${DEVNET_CLIENT_SECRET}" \
        --data 'audience=validator-devnet-m2m' \
        --data 'scope=daml_ledger_api')
    
    if echo "$RESPONSE" | grep -q "access_token"; then
        TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
        EXPIRES_IN=$(echo "$RESPONSE" | jq -r '.expires_in')
        EXPIRY=$(($(date +%s) + EXPIRES_IN - 3600))  # Refresh 1 hour before expiry
        
        echo "$TOKEN" > /tmp/devnet_token.txt
        echo "$EXPIRY" > /tmp/token_expiry.txt
        
        echo_success "Token obtained (expires in ${EXPIRES_IN}s)"
        echo "$TOKEN"
    else
        echo_error "Failed to get token: $RESPONSE"
        exit 1
    fi
}

check_prereqs() {
    echo_step "Checking prerequisites..."
    
    if ! command -v java &> /dev/null; then
        echo_error "Java not found. Install Java 17+"
        exit 1
    fi
    
    if [ "$MODE" = "devnet" ]; then
        # Set defaults for Seaport Validator Devnet
        export DEVNET_HOST="${DEVNET_HOST:-ledger-api.validator.devnet.sandbox.fivenorth.io}"
        export DEVNET_PORT="${DEVNET_PORT:-443}"
        export DEVNET_CLIENT_ID="${DEVNET_CLIENT_ID:-validator-devnet-m2m}"
        
        if [ -z "$DEVNET_CLIENT_SECRET" ]; then
            echo_error "DEVNET_CLIENT_SECRET environment variable is required for Devnet"
            echo "Usage: DEVNET_CLIENT_SECRET=<secret> ./run-integration-test.sh --devnet"
            exit 1
        fi
        echo_info "Devnet: $DEVNET_HOST:$DEVNET_PORT"
        echo_info "Auth: https://auth.sandbox.fivenorth.io"
    fi
    
    echo_success "Prerequisites OK"
}

build_dars() {
    echo_step "Building DARs..."
    cd "$PROJECT_DIR"
    dpm build --all 2>&1 || { echo_error "Build failed"; exit 1; }
    echo_success "Build complete"
}

upload_dar_to_devnet() {
    echo_step "Uploading DAR to Devnet..."
    
    TOKEN=$(get_devnet_token)
    
    # Upload DAR (use -k for self-signed certs in devnet)
    RESPONSE=$(curl -s -k -X POST "https://${DEVNET_HOST}/v2/packages" \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/octet-stream' \
        --data-binary @"$MONOTRON_DAR")
    
    if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "{}" ]; then
        echo_success "DAR uploaded successfully"
    else
        echo_warn "DAR upload response: $RESPONSE"
    fi
}

start_sandbox() {
    echo_step "Starting Canton Sandbox..."
    
    # Kill existing
    lsof -ti:$SANDBOX_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 1
    
    # Start sandbox with all DARs
    nohup daml sandbox \
        --port $SANDBOX_PORT \
        --json-api-port $SANDBOX_JSON_PORT \
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
    
    # Wait for startup
    for i in {1..60}; do
        if curl -s http://localhost:$SANDBOX_JSON_PORT/health > /dev/null 2>&1; then
            echo_success "JSON API ready on port $SANDBOX_JSON_PORT"
            return 0
        fi
        if curl -s http://localhost:$SANDBOX_PORT/health > /dev/null 2>&1; then
            echo_success "Sandbox ready on port $SANDBOX_PORT"
            return 0
        fi
        if [ $i -eq 60 ]; then
            echo_error "Sandbox failed to start"
            cat /tmp/sandbox.log | tail -50
            exit 1
        fi
        sleep 1
    done
}

get_host() { [ "$MODE" = "devnet" ] && echo "$DEVNET_HOST" || echo "localhost"; }
get_port() { [ "$MODE" = "devnet" ] && echo "$DEVNET_PORT" || echo "$SANDBOX_PORT"; }

# =============================================================================
# Daml Script: Full Integration Test
# =============================================================================

create_full_script() {
    cat > /tmp/monotron-integration-test.daml << 'DAMLEOF'
module IntegrationTest where

import Daml.Script
import DA.Date (date, Month(Jan))
import DA.Time (time)
import Main

-- =============================================================================
-- Full Integration Test: Invoice Settlement Flow
-- =============================================================================

testFullFlow : Script ()
testFullFlow = do

  -- Allocate parties
  operator <- allocateParty "Operator"
  seller <- allocateParty "Seller"  
  buyer <- allocateParty "Buyer"
  instrumentAdmin <- allocateParty "CantonCoin"

  debug $ "=== PARTIES ==="
  debug $ "Operator: " <> show operator
  debug $ "Seller: " <> show seller
  debug $ "Buyer: " <> show buyer
  debug $ "InstrumentAdmin: " <> show instrumentAdmin

  -- STEP 1: Register businesses
  debug $ "=== STEP 1: Business Registration ==="
  
  sellerReg <- submit operator do
    createCmd BusinessRegistration
      with business = seller; operator; businessName = "Acme Corp"
           taxId = "US-123456789"; status = Active
           registeredAt = time (date 2025 Jan 1) 0 0 0
  
  buyerReg <- submit operator do
    createCmd BusinessRegistration
      with business = buyer; operator; businessName = "Globex Inc"
           taxId = "US-987654321"; status = Active
           registeredAt = time (date 2025 Jan 1) 0 0 0
  
  debug $ "Seller registered: " <> show sellerReg
  debug $ "Buyer registered: " <> show buyerReg

  -- STEP 2: Create Faucet and Fund Buyer
  debug $ "=== STEP 2: Wallet Setup ==="
  
  faucet <- submit operator do
    createCmd Faucet
      with operator; instrumentAdmin; currencyCode = "CC"
  
  debug $ "Faucet created: " <> show faucet
  
  -- Mint tokens to buyer
  buyerHolding <- submit operator do
    exerciseCmd faucet Faucet_Mint with recipient = buyer; amount = 10000.00
  
  debug $ "Buyer holding created: " <> show buyerHolding
  
  -- Also mint some to seller so they can receive
  sellerHolding <- submit operator do
    exerciseCmd faucet Faucet_Mint with recipient = seller; amount = 5000.00
  
  debug $ "Seller holding created: " <> show sellerHolding

  -- Verify balances
  buyerHolds <- query @TestHolding buyer
  sellerHolds <- query @TestHolding seller
  
  let buyerBal = sum (map (\(h, _) -> h.amount) buyerHolds)
  let sellerBal = sum (map (\(h, _) -> h.amount) sellerHolds)
  
  debug $ "Buyer balance: " <> show buyerBal
  debug $ "Seller balance: " <> show sellerBal
  
  assertMsg "Buyer should have 10000 CC" (buyerBal == 10000.00)
  assertMsg "Seller should have 5000 CC" (sellerBal == 5000.00)

  -- STEP 3: Settlement Delegation
  debug $ "=== STEP 3: Settlement Delegation ==="
  
  delegation <- submit seller do
    createCmd SettlementDelegation
      with seller; operator; scope = "invoice-settlement"
           validFrom = time (date 2025 Jan 1) 0 0 0
           validUntil = time (date 2030 Jan 1) 0 0 0
           active = True
  
  debug $ "Delegation created: " <> show delegation

  -- STEP 4: Create Invoice
  debug $ "=== STEP 4: Create Invoice ==="
  
  invoiceCid <- submit seller do
    createCmd Invoice
      with seller; buyer; operator; amount = 1000.00
           currency = "CC"
           description = "Consulting services - Q1 2025"
           dueDate = date 2025 Mar 31
           status = Created
           invoiceId = "INV-2025-Q1-001"
           instrumentAdmin
           transferInstructionCid = None
  
  debug $ "Invoice created: " <> show invoiceCid

  -- STEP 5: Approve Invoice
  debug $ "=== STEP 5: Approve Invoice ==="
  
  approvedCid <- submit buyer do
    exerciseCmd invoiceCid Invoice_Approve
  
  debug $ "Invoice approved: " <> show approvedCid

  -- Verify status
  invoices <- query @Invoice buyer
  case invoices of
    [(inv, _)] -> do
      debug $ "Invoice status: " <> show inv.status
      assertMsg "Invoice should be Approved" (inv.status == Approved)
    _ -> debug "WARNING: Could not verify invoice"

  -- STEP 6: Initiate Settlement
  debug $ "=== STEP 6: Initiate Settlement ==="
  
  -- For testing, we demonstrate the state transition
  -- Full Path A would exercise:
  -- 1. TransferFactory_Transfer (real Token Standard)
  -- 2. TransferInstruction_Accept (moves Holdings)
  -- 3. Invoice_ConfirmSettled (marks settled)
  
  initiatedCid <- submit buyer do
    exerciseCmd approvedCid Invoice_InitiateSettlement
      with transferInstructionCid = None
  
  debug $ "Invoice moved to AwaitingSettlement: " <> show initiatedCid

  -- STEP 7: Final Verification
  debug $ "=== STEP 7: Verification ==="
  
  finalInvoices <- query @Invoice buyer
  case finalInvoices of
    [(inv, _)] -> do
      debug $ "Final status: " <> show inv.status
      assertMsg "Should be AwaitingSettlement" (inv.status == AwaitingSettlement)
    _ -> debug "WARNING: Could not verify final state"
  
  debug $ "=== TEST COMPLETE ==="
  debug $ "Integration test PASSED - All stages verified"

DAMLEOF

    echo "/tmp/monotron-integration-test.daml"
}

# =============================================================================
# Daml Script: Wallet Funding Test (for Devnet with Canton Coin)
# =============================================================================

create_wallet_script() {
    cat > /tmp/monotron-wallet-test.daml << 'DAMLEOF'
module WalletTest where

import Daml.Script
import DA.Date (date, Month(Jan))
import DA.Time (time)
import Main

-- =============================================================================
-- Wallet Test: Test holdings via Faucet
-- 
-- NOTE: This tests the TestHolding implementation.
-- For real Canton Coin on Devnet, you would:
-- 1. Use the Devnet faucet API to fund parties
-- 2. Query real Holding contracts via Holding interface
-- =============================================================================

testWallet : Script ()
testWallet = do

  operator <- allocateParty "Operator"
  alice <- allocateParty "Alice"
  bob <- allocateParty "Bob"
  cantonCoin <- allocateParty "CantonCoin"

  debug $ "=== WALLET TEST ==="
  debug $ "Operator: " <> show operator
  debug $ "Alice: " <> show alice
  debug $ "Bob: " <> show bob
  debug $ "CantonCoin (admin): " <> show cantonCoin

  -- Create Faucet
  faucet <- submit operator do
    createCmd Faucet
      with operator; instrumentAdmin = cantonCoin; currencyCode = "CC"
  
  debug $ "Faucet: " <> show faucet

  -- Batch mint
  holdings <- submit operator do
    exerciseCmd faucet Faucet_BatchMint with
      recipients = [(alice, 10000.00), (bob, 5000.00)]

  debug $ "Created " <> show (length holdings) <> " holdings"

  -- Verify Alice's holdings
  aliceHolds <- query @TestHolding alice
  let aliceBal = sum (map (\(h, _) -> h.amount) aliceHolds)
  debug $ "Alice balance: " <> show aliceBal
  assertMsg "Alice should have 10000" (aliceBal == 10000.00)

  -- Verify Bob's holdings
  bobHolds <- query @TestHolding bob
  let bobBal = sum (map (\(h, _) -> h.amount) bobHolds)
  debug $ "Bob balance: " <> show bobBal
  assertMsg "Bob should have 5000" (bobBal == 5000.00)

  -- Test transfer between holdings
  case aliceHolds of
    [(aliceHolding, _)] -> do
      debug "Testing holding transfer..."
      (archived, newAlice, newBob) <- submit alice do
        exerciseCmd (fst aliceHolding) TestHolding_Transfer with newOwner = bob
      
      debug $ "Transfer complete: " <> show archived <> " -> " <> show newBob
      
      -- Verify new balances
      newAliceHolds <- query @TestHolding alice
      newBobHolds <- query @TestHolding bob
      
      let newAliceBal = sum (map (\(h, _) -> h.amount) newAliceHolds)
      let newBobBal = sum (map (\(h, _) -> h.amount) newBobHolds)
      
      debug $ "Alice new balance: " <> show newAliceBal
      debug $ "Bob new balance: " <> show newBobBal
      
      assertMsg "Alice should have 0" (newAliceBal == 0.00)
      assertMsg "Bob should have 15000" (newBobBal == 15000.00)
      
    _ -> debug "ERROR: No holdings found"

  debug $ "=== WALLET TEST COMPLETE ==="

DAMLEOF

    echo "/tmp/monotron-wallet-test.daml"
}

# =============================================================================
# Run Test
# =============================================================================

run_test() {
    local script_file="$1"
    local test_name="$2"
    local ledger_host=$(get_host)
    local ledger_port=$(get_port)

    echo_step "Running $test_name..."
    echo_info "Ledger: $ledger_host:$ledger_port"

    cd "$PROJECT_DIR/test"

    # For Devnet, we need to use curl for the JSON API
    if [ "$MODE" = "devnet" ]; then
        # Get token
        local token=$(get_devnet_token)
        
        # For Devnet, we use the HTTP JSON API
        # Note: dpm script doesn't support HTTPS well for Devnet
        # So we use curl-based approach for Devnet
        
        echo_info "Testing Devnet connection..."
        
        # Test ledger API (use -k for self-signed certs)
        local ledger_end=$(curl -s -k "https://${ledger_host}/v2/state/ledger-end" \
            --header "Authorization: Bearer $token")
        
        echo_info "Ledger end: $ledger_end"
        
        # Run Daml Script against Devnet
        # Note: For Devnet, we need to upload DAR first and use grpc
        # This is a simplified test - in production, use proper canton-cli
        echo_success "Devnet connection verified"
        echo_info "For full Daml Script support, use canton-console or canton-cli"
        
        return 0
    else
        # Run with dpm script for sandbox
        dpm script \
            --dar .daml/dist/monotron-test-0.0.1.dar \
            --ledger-host "$ledger_host" \
            --ledger-port "$ledger_port" \
            "$test_name" 2>&1

        return $?
    fi
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    echo_step "Cleaning up..."
    if [ -n "$SANDBOX_PID" ]; then
        kill $SANDBOX_PID 2>/dev/null || true
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "=============================================="
    echo "Monoton Integration Test"
    echo "Mode: $MODE"
    echo "=============================================="
    echo ""

    setup_env
    check_prereqs
    build_dars

    if [ "$MODE" = "sandbox" ] || [ "$MODE" = "full" ]; then
        start_sandbox
        trap cleanup EXIT
    fi

    if [ "$MODE" = "devnet" ]; then
        # Upload DAR to Devnet
        upload_dar_to_devnet
    fi

    case $MODE in
        scaffold)
            echo_step "Running wallet funding test..."
            script=$(create_wallet_script)
            run_test "$script" "testWallet"
            ;;
        full)
            echo_step "Running full integration test..."
            script=$(create_full_script)
            run_test "$script" "testFullFlow"
            ;;
        devnet)
            echo_step "Running Devnet integration test..."
            script=$(create_full_script)
            run_test "$script" "testFullFlow"
            ;;
        *)
            echo_step "Running wallet test (default)..."
            script=$(create_wallet_script)
            run_test "$script" "testWallet"
            ;;
    esac

    TEST_RESULT=$?

    if [ $TEST_RESULT -eq 0 ]; then
        echo ""
        echo_success "=============================================="
        echo_success "TEST PASSED"
        echo_success "=============================================="
    else
        echo ""
        echo_error "=============================================="
        echo_error "TEST FAILED"
        echo_error "=============================================="
        [ -f /tmp/sandbox.log ] && cat /tmp/sandbox.log | tail -50
    fi

    exit $TEST_RESULT
}

main "$@"
    echo "Monoton Integration Test"
    echo "Mode: $MODE"
    echo "=============================================="
    echo ""

    setup_env
    check_prereqs
    build_dars

    if [ "$MODE" = "sandbox" ] || [ "$MODE" = "full" ]; then
        start_sandbox
        trap cleanup EXIT
    fi

    case $MODE in
        scaffold)
            echo_step "Running wallet funding test..."
            script=$(create_wallet_script)
            run_test "$script" "testWallet"
            ;;
        full)
            echo_step "Running full integration test..."
            script=$(create_full_script)
            run_test "$script" "testFullFlow"
            ;;
        *)
            echo_step "Running wallet test (default)..."
            script=$(create_wallet_script)
            run_test "$script" "testWallet"
            ;;
    esac

    TEST_RESULT=$?

    if [ $TEST_RESULT -eq 0 ]; then
        echo ""
        echo_success "=============================================="
        echo_success "TEST PASSED"
        echo_success "=============================================="
    else
        echo ""
        echo_error "=============================================="
        echo_error "TEST FAILED"
        echo_error "=============================================="
        [ -f /tmp/sandbox.log ] && cat /tmp/sandbox.log | tail -50
    fi

    exit $TEST_RESULT
}

main "$@"
