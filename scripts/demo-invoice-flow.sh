#!/bin/bash
# =============================================================================
# Monotron Invoice Settlement Flow - JSON API Demo
# =============================================================================
# Demonstrates the full invoice lifecycle using the JSON API
#
# Flow: Created → Approved → AwaitingSettlement → Settled
# =============================================================================

set -e

LEDGER_HOST="${LEDGER_HOST:-localhost}"
LEDGER_PORT="${LEDGER_PORT:-7575}"
API_BASE="http://${LEDGER_HOST}:${LEDGER_PORT}"

echo_step() { echo -e "\033[0;32m[STEP]\033[0m $1"; }
echo_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
echo_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
echo_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# =============================================================================
# Get ledger end
# =============================================================================

get_ledger_end() {
    curl -s "${API_BASE}/v2/state/ledger-end"
}

# =============================================================================
# Allocate parties
# =============================================================================

allocate_party() {
    local party="$1"
    echo_step "Allocating party: $party"
    
    RESULT=$(curl -s -X POST "${API_BASE}/v2/commands" \
        -H "Content-Type: application/json" \
        -d "{
            \"commands\": {
                \"commandId\": \"allocate-${party}-$(date +%s)\",
                \"party\": \"${party}\",
                \"applicationId\": \"monotron-json-demo\",
                \"actAs\": [\"${party}\"],
                \"readAs\": [],
                \"workflowId\": \"party-allocation\",
                \"command\": {
                    \"create\": {
                        \"templateId\": {
                            \"packageId\": \"\",
                            \"moduleName\": \"\",
                            \"entityName\": \"Party\"
                        },
                        \"arguments\": {}
                    }
                }
            }
        }" 2>&1)
    
    echo_info "Result: $RESULT"
}

# =============================================================================
# Create Faucet
# =============================================================================

create_faucet() {
    echo_step "Creating Faucet contract..."
    
    # First get the ledger end
    LEDGER_END=$(get_ledger_end)
    
    RESULT=$(curl -s -X POST "${API_BASE}/v2/commands" \
        -H "Content-Type: application/json" \
        -d "{
            \"commands\": {
                \"commandId\": \"create-faucet-$(date +%s)\",
                \"party\": \"Operator\",
                \"applicationId\": \"monotron-json-demo\",
                \"actAs\": [\"Operator\"],
                \"readAs\": [\"Operator\"],
                \"workflowId\": \"monotron-setup\",
                \"command\": {
                    \"create\": {
                        \"templateId\": {
                            \"packageId\": \"\",
                            \"moduleName\": \"Main\",
                            \"entityName\": \"Faucet\"
                        },
                        \"arguments\": {
                            \"operator\": \"Operator\",
                            \"instrumentAdmin\": \"Operator\",
                            \"currencyCode\": \"CC\"
                        }
                    }
                }
            }
        }")
    
    echo_info "Result: $RESULT"
    TX_ID=$(echo "$RESULT" | jq -r '.result.transactionId // empty')
    if [ -n "$TX_ID" ]; then
        echo_success "Faucet created! Transaction: $TX_ID"
    else
        echo_error "Failed to create faucet"
        echo "$RESULT"
    fi
}

# =============================================================================
# Create Business Registration
# =============================================================================

create_business() {
    local business="$1"
    local name="$2"
    
    echo_step "Registering business: $name"
    
    RESULT=$(curl -s -X POST "${API_BASE}/v2/commands" \
        -H "Content-Type: application/json" \
        -d "{
            \"commands\": {
                \"commandId\": \"create-biz-${business}-$(date +%s)\",
                \"party\": \"Operator\",
                \"applicationId\": \"monotron-json-demo\",
                \"actAs\": [\"Operator\"],
                \"readAs\": [],
                \"workflowId\": \"monotron-setup\",
                \"command\": {
                    \"create\": {
                        \"templateId\": {
                            \"packageId\": \"\",
                            \"moduleName\": \"Main\",
                            \"entityName\": \"BusinessRegistration\"
                        },
                        \"arguments\": {
                            \"business\": \"${business}\",
                            \"operator\": \"Operator\",
                            \"businessName\": \"${name}\",
                            \"taxId\": \"TAX-${business}-001\",
                            \"status\": { \"tag\": \"Active\" },
                            \"registeredAt\": { \"value\": \"2026-07-09T00:00:00Z\" }
                        }
                    }
                }
            }
        }")
    
    echo_info "Result: $RESULT"
}

# =============================================================================
# Create Invoice
# =============================================================================

create_invoice() {
    echo_step "Creating Invoice..."
    
    RESULT=$(curl -s -X POST "${API_BASE}/v2/commands" \
        -H "Content-Type: application/json" \
        -d "{
            \"commands\": {
                \"commandId\": \"create-invoice-$(date +%s)\",
                \"party\": \"Seller\",
                \"applicationId\": \"monotron-json-demo\",
                \"actAs\": [\"Seller\"],
                \"readAs\": [],
                \"workflowId\": \"monotron-invoice\",
                \"command\": {
                    \"create\": {
                        \"templateId\": {
                            \"packageId\": \"\",
                            \"moduleName\": \"Main\",
                            \"entityName\": \"Invoice\"
                        },
                        \"arguments\": {
                            \"seller\": \"Seller\",
                            \"buyer\": \"Buyer\",
                            \"operator\": \"Operator\",
                            \"invoiceNumber\": \"INV-2026-DEMO-001\",
                            \"description\": \"B2B Invoice for software services - Canton Hackathon Demo\",
                            \"amount\": 5000.00,
                            \"currencyCode\": \"CC\",
                            \"dueDate\": { \"value\": \"2026-07-30T00:00:00Z\" },
                            \"instrumentAdmin\": \"Operator\",
                            \"status\": { \"tag\": \"Created\" },
                            \"createdAt\": { \"value\": \"2026-07-09T00:00:00Z\" }
                        }
                    }
                }
            }
        }")
    
    echo_info "Result: $RESULT"
    TX_ID=$(echo "$RESULT" | jq -r '.result.transactionId // empty')
    if [ -n "$TX_ID" ]; then
        echo_success "Invoice created! Transaction: $TX_ID"
    fi
}

# =============================================================================
# Query Active Contracts
# =============================================================================

query_contracts() {
    local party="$1"
    echo_step "Querying active contracts for $party..."
    
    RESULT=$(curl -s -X POST "${API_BASE}/v2/state/active-contracts" \
        -H "Content-Type: application/json" \
        -d "{
            \"activeAtOffset\": \"\",
            \"eventFormat\": {
                \"filtersByParty\": {
                    \"${party}\": {
                        \"cumulative\": [{
                            \"activeContractsIncludeArchivedAtOffset\": false,
                            \"activeContractsFilter\": [{
                                \"moduleFilter\": \"*\",
                                \"templateFilter\": \"*\"
                            }]
                        }]
                    }
                }
            },
            \"verbose\": true
        }")
    
    echo_info "Found $(echo "$RESULT" | jq 'length') workflows"
    echo "$RESULT" | jq '.[] | "\(.workflowId // .contractId): \(.templateId.moduleName):\(.templateId.entityName)"' 2>/dev/null | head -20
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "=============================================="
    echo "Monotron Invoice Settlement Flow Demo"
    echo "=============================================="
    echo ""
    
    # Check ledger
    echo_step "Checking ledger connection..."
    LEDGER_END=$(get_ledger_end)
    echo_info "Ledger end: $LEDGER_END"
    echo ""
    
    # Create contracts
    echo "--- Setup Phase ---"
    create_faucet
    create_business "Seller" "ACME Corporation"
    create_business "Buyer" "Global Imports Ltd"
    echo ""
    
    # Create invoice
    echo "--- Invoice Creation Phase ---"
    create_invoice
    echo ""
    
    # Query contracts
    echo "--- Active Contracts ---"
    query_contracts "Operator"
    query_contracts "Seller"
    query_contracts "Buyer"
    echo ""
    
    echo_success "=============================================="
    echo_success "Demo Complete!"
    echo_success "=============================================="
    echo ""
    echo "Next steps:"
    echo "1. Buyer approves invoice: Exercise Invoice_Approve"
    echo "2. Buyer initiates settlement: Exercise Invoice_InitiateSettlement"
    echo "3. Operator confirms: Exercise Invoice_ConfirmSettled"
    echo ""
    echo "Run: curl -X POST http://localhost:7575/v2/commands ..."
}

main "$@"
