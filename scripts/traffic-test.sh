#!/usr/bin/env bash
# traffic-test.sh
# Send configurable HTTP requests to the load balancer public IP and summarize status codes.
# Requires: curl, az login (for public IP lookup), appropriate RBAC

set -euo pipefail

# Configuration - UPDATE THESE VALUES
RESOURCE_GROUP="rg-t087-chaos-resilience"
LB_PUBLIC_IP_NAME="lb-t087-chaos-resilience-publicip"
DEFAULT_REQUESTS=20
DEFAULT_TIMEOUT=5
DEFAULT_CONCURRENCY=1
# Public IP placeholder - resolve from Azure or provide via env var / CLI
DEFAULT_PUBLIC_IP_PLACEHOLDER="<LOAD_BALANCER_PUBLIC_IP>"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Send HTTP requests to the Azure Load Balancer public IP and summarize results.

Options:
    -g, --resource-group NAME    Resource group name (default: $RESOURCE_GROUP)
    -i, --ip-name NAME           Public IP resource name (default: $LB_PUBLIC_IP_NAME)
    -r, --requests N             Number of requests to send (default: $DEFAULT_REQUESTS)
    -t, --timeout SECONDS        Request timeout in seconds (default: $DEFAULT_TIMEOUT)
    -c, --concurrency N          Concurrent requests (default: $DEFAULT_CONCURRENCY)
    -u, --url URL                Direct URL to test (bypasses IP lookup)
    -p, --path PATH              HTTP path (default: /)
    -H, --header HEADER          Additional header (can repeat)
    -v, --verbose                Show each request result
    -h, --help                   Show this help

Examples:
    $0
    $0 -r 100 -t 10 -c 5
    $0 -u "http://<LOAD_BALANCER_PUBLIC_IP>/health"
    $0 --header "Host: myapp.example.com" --header "User-Agent: chaos-test"
EOF
}

# Parse arguments
REQUESTS=$DEFAULT_REQUESTS
TIMEOUT=$DEFAULT_TIMEOUT
CONCURRENCY=$DEFAULT_CONCURRENCY
URL=""
PATH="/"
HEADERS=()
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -i|--ip-name)
            LB_PUBLIC_IP_NAME="$2"
            shift 2
            ;;
        -r|--requests)
            REQUESTS="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -c|--concurrency)
            CONCURRENCY="$2"
            shift 2
            ;;
        --public-ip)
            PUBLIC_IP_FROM_ARG="$2"
            shift 2
            ;;
        -p|--path)
            PATH="$2"
            shift 2
            ;;
        -H|--header)
            HEADERS+=("$2")
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            usage
            exit 1
            ;;
    esac
done

# Validate numeric arguments
if ! [[ "$REQUESTS" =~ ^[0-9]+$ ]] || [[ "$REQUESTS" -lt 1 ]]; then
    echo -e "${RED}Error: --requests must be a positive integer${NC}" >&2
    exit 1
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -lt 1 ]]; then
    echo -e "${RED}Error: --timeout must be a positive integer${NC}" >&2
    exit 1
fi

if ! [[ "$CONCURRENCY" =~ ^[0-9]+$ ]] || [[ "$CONCURRENCY" -lt 1 ]]; then
    echo -e "${RED}Error: --concurrency must be a positive integer${NC}" >&2
    exit 1
fi

# Resolve public IP: env var > CLI arg > Azure CLI lookup
if [[ -n "${PUBLIC_IP:-}" ]]; then
    PUBLIC_IP="$PUBLIC_IP"
    echo -e "${GREEN}PUBLIC_IP from environment variable${NC}"
elif [[ -n "${PUBLIC_IP_FROM_ARG:-}" ]]; then
    PUBLIC_IP="$PUBLIC_IP_FROM_ARG"
    echo -e "${GREEN}PUBLIC_IP from --public-ip argument${NC}"
else
    echo -e "${BLUE}Looking up public IP...${NC}"
    PUBLIC_IP=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LB_PUBLIC_IP_NAME" \
        --query "ipAddress" -o tsv 2>/dev/null)

    if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "null" ]]; then
        echo -e "${RED}Error: Could not resolve public IP for '$LB_PUBLIC_IP_NAME' in RG '$RESOURCE_GROUP'${NC}" >&2
        echo -e "${YELLOW}Set PUBLIC_IP env var, provide --public-ip, or check resource names.${NC}" >&2
        exit 1
    fi
fi

# Build the target URL
URL="http://${PUBLIC_IP}${PATH}"

echo -e "${BLUE}=== Traffic Test Configuration ===${NC}"
echo -e "  Requests:     ${YELLOW}$REQUESTS${NC}"
echo -e "  Timeout:      ${YELLOW}${TIMEOUT}s${NC}"
echo -e "  Concurrency:  ${YELLOW}$CONCURRENCY${NC}"
echo -e "  URL:          ${YELLOW}$URL${NC}"
if [[ ${#HEADERS[@]} -gt 0 ]]; then
    echo -e "  Headers:"
    for h in "${HEADERS[@]}"; do
        echo -e "    ${YELLOW}$h${NC}"
    done
fi
echo ""

# Build curl command
CURL_CMD="curl -s -o /dev/null -w '%{http_code}' --max-time $TIMEOUT"
for h in "${HEADERS[@]}"; do
    CURL_CMD="$CURL_CMD -H '$h'"
done
CURL_CMD="$CURL_CMD '$URL'"

# Run requests
echo -e "${BLUE}=== Running $REQUESTS requests ===${NC}"

# Arrays to store results
declare -a RESULTS
declare -a ERRORS

run_request() {
    local i=$1
    local output
    local exit_code

    output=$(eval "$CURL_CMD" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        RESULTS+=("$output")
        if [[ "$VERBOSE" == true ]]; then
            echo -e "  Request $i: ${GREEN}$output${NC}"
        fi
    else
        ERRORS+=("$i: curl exit $exit_code - $output")
        if [[ "$VERBOSE" == true ]]; then
            echo -e "  Request $i: ${RED}FAILED (curl exit $exit_code)${NC}"
        fi
    fi
}

# Run with concurrency control
if [[ $CONCURRENCY -eq 1 ]]; then
    # Sequential
    for i in $(seq 1 "$REQUESTS"); do
        run_request "$i"
    done
else
    # Parallel using background jobs
    pids=()
    for i in $(seq 1 "$REQUESTS"); do
        run_request "$i" &
        pids+=($!)

        # Limit concurrency
        if [[ ${#pids[@]} -ge $CONCURRENCY ]]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
        fi
    done
    # Wait for remaining
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
fi

# Summarize results
echo ""
echo -e "${BLUE}=== Results Summary ===${NC}"

TOTAL=${#RESULTS[@]}
FAILED=${#ERRORS[@]}
SUCCESS=0

# Count by status code
declare -a CODES
for code in "${RESULTS[@]}"; do
    CODES["$code"]=$((${CODES["$code"]:-0} + 1))
    if [[ "$code" -ge 200 && "$code" -lt 300 ]]; then
        SUCCESS=$((SUCCESS + 1))
    fi
done

echo -e "  Total requests:     ${YELLOW}$REQUESTS${NC}"
echo -e "  Successful (2xx):   ${GREEN}$SUCCESS${NC}"
echo -e "  Failed (non-2xx):   ${RED}$((TOTAL - SUCCESS))${NC}"
echo -e "  Connection errors:  ${RED}$FAILED${NC}"
echo ""

if [[ ${#CODES[@]} -gt 0 ]]; then
    echo -e "${BLUE}Status code breakdown:${NC}"
    for code in $(printf '%s\n' "${!CODES[@]}" | sort -n); do
        count=${CODES[$code]}
        if [[ "$code" -ge 200 && "$code" -lt 300 ]]; then
            echo -e "  ${GREEN}$code${NC}: $count"
        elif [[ "$code" -ge 400 && "$code" -lt 500 ]]; then
            echo -e "  ${YELLOW}$code${NC}: $count"
        elif [[ "$code" -ge 500 && "$code" -lt 600 ]]; then
            echo -e "  ${RED}$code${NC}: $count"
        else
            echo -e "  $code: $count"
        fi
    done
fi

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo -e "${RED}Connection errors:${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "  ${RED}$err${NC}"
    done
fi

# Availability calculation
if [[ $REQUESTS -gt 0 ]]; then
    AVAILABILITY=$(awk "BEGIN {printf \"%.2f\", ($SUCCESS / $REQUESTS) * 100}")
    echo ""
    echo -e "${CYAN}Availability (2xx / total): ${AVAILABILITY}%${NC}"
    echo -e "${YELLOW}Note: $REQUESTS sampled requests do not establish a 100% availability guarantee.${NC}"
fi

# Exit code based on results
if [[ $SUCCESS -eq $REQUESTS && $FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi