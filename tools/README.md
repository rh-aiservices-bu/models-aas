# Tools to interact with MaaS

## Service Activation

3Scale 2.14 does not have a way to automatically subscribe new Services/Products to all existing accounts. These tools provide automated solutions using the admin API.

### Files

- `activate_service.ipynb` - Interactive notebook for single service activation
- `activate_service_all_accounts.ipynb` - Interactive notebook for activating one service across all accounts  
- `activate_all_services.py` - Production script for activating all services across all accounts
- `activate_service_functions.py` - Shared API functions

### How Service Activation Works

The activation process uses a "dummy application" technique:

1. **Create** a temporary application for the account using the service plan
2. **Delete** the application immediately 

This creates a subscription between the account and service that persists even after the application is deleted, effectively activating the service for that account.

### activate_all_services.py

Production-ready script that activates all available services for all accounts.

#### Usage

```bash
# Test on single account first (recommended)
python activate_all_services.py --account-id 123

# Process all accounts
python activate_all_services.py

# Activate specific service/plan for all accounts
python activate_all_services.py --service-id 5 --plan-id 12

# Test specific service/plan on single account
python activate_all_services.py --account-id 123 --service-id 5 --plan-id 12
```

#### Features

- **Bulk Processing**: Activates all services for all accounts automatically
- **Specific Service Mode**: Target individual service/plan combinations
- **Test Mode**: Safe testing on single account before bulk operation
- **Flexible Combinations**: All modes can be combined (test + specific service)
- **Progress Tracking**: Real-time progress updates and statistics
- **Comprehensive Logging**: Logs to both file and console with detailed status
- **Error Handling**: Continues processing on individual failures
- **Validation**: Validates accounts, services, and service/plan compatibility

#### Process Flow

1. Fetch all accounts from 3Scale API (handles pagination)
2. Fetch all available services
3. Fetch all service plans and match to services
4. For each account:
   - For each service:
     - Create dummy application with service plan
     - Delete the application (subscription remains)
     - Log success/failure
5. Generate comprehensive summary report

#### Environment Setup

Requires `.env` file with:

```env
BACKEND_ADDRESS=https://your-3scale-admin.example.com
ACCESS_TOKEN=your_admin_api_token
```

#### Output

- **Console**: Real-time progress and summary
- **Log File**: `activate_all_services.log` with detailed execution log
- **Statistics**: Success/failure counts and rates
- **Exit Codes**: 0 for success, 1 for failures

#### Example Output

**Test Mode (All Services):**

```text
TEST MODE: Activating all services for account ID 7
Found 794 accounts
Found target account: gmoutier@redhat.com (ID: 7)
Found 16 services
TEST MODE: 16 operations for 1 account
✓ Activated Granite-8B-Code-Instruct
✓ Activated Mistral-7B-Instruct-v0.3
...
✓ TEST PASSED: All services activated successfully!
```

**Specific Service Mode:**

```text
SPECIFIC SERVICE MODE: Activating service 5 (plan 12) for all accounts
Found 794 accounts
Validated service/plan: Nomic-embed-text-v1.5 (ID: 5) with plan 12
Service to be activated: Nomic-embed-text-v1.5 (ID: 5)
SPECIFIC SERVICE MODE: 794 operations (1 service for 794 accounts)
✓ Activated Nomic-embed-text-v1.5
...
All services activated successfully!
```
