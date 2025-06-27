#!/usr/bin/env python3
"""
Activate All Services for All Accounts

This script activates all available services for all accounts in a 3Scale instance
by subscribing each account to each service plan.

Usage:
    python activate_all_services.py                          # Activate all services for all accounts
    python activate_all_services.py --account-id 123         # Test on specific account
    python activate_all_services.py --service-id 5 --plan-id 12  # Activate specific service/plan for all accounts
    python activate_all_services.py --account-id 123 --service-id 5 --plan-id 12  # Test specific service/plan on one account
"""

import sys
import argparse
import logging
from typing import List, Dict, Tuple, Optional, Any
import activate_service_functions as asf

def setup_logging():
    """Configure logging for the script."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('activate_all_services.log'),
            logging.StreamHandler(sys.stdout)
        ]
    )
    return logging.getLogger(__name__)

def get_all_service_plans(services: Dict[str, Any], plans: Dict[str, Any]) -> List[Tuple[int, int]]:
    """
    Get all service-plan combinations.
    
    Returns:
        List of tuples (service_id, plan_id)
    """
    service_plan_pairs = []
    
    for service in services["services"]["service"]:
        service_id = int(service["id"])
        plan_id = asf.get_service_plan_by_service_id(plans, service_id)
        if plan_id:
            service_plan_pairs.append((service_id, plan_id))
    
    return service_plan_pairs

def activate_service_for_account(account_id: int, service_id: int, plan_id: int, logger) -> bool:
    """
    Activate a single service for a single account.
    
    Returns:
        True if successful, False otherwise
    """
    try:
        application_id = int(asf.create_dummy_application(account_id, plan_id))
        response = asf.delete_application(account_id, application_id)
        
        if response.status_code == 200:
            return True
        else:
            logger.error(f"Failed to delete application {application_id} for account {account_id}, service {service_id}")
            logger.error(f"Response: {response.content}")
            return False
            
    except Exception as e:
        logger.error(f"Error activating service {service_id} for account {account_id}: {e}")
        return False

def find_account_by_id(accounts: Dict[str, Any], target_account_id: int) -> Optional[Dict[str, Any]]:
    """Find a specific account by ID."""
    for account in accounts["accounts"]["account"]:
        if int(account["id"]) == target_account_id:
            return account
    return None

def process_accounts(accounts_to_process: List[Dict[str, Any]], services: Dict[str, Any], service_plan_pairs: List[Tuple[int, int]], logger, test_mode: bool = False) -> Tuple[int, int]:
    """Process a list of accounts and return success/failure counts."""
    successful_operations = 0
    failed_operations = 0
    account_count = len(accounts_to_process)
    
    for i, account in enumerate(accounts_to_process, 1):
        account_id = int(account["id"])
        org_name = account.get("org_name", "Unknown")
        
        mode_text = "TEST MODE - " if test_mode else ""
        logger.info(f"{mode_text}Processing account {i}/{account_count}: {org_name} (ID: {account_id})")
        
        account_successes = 0
        account_failures = 0
        
        # Activate each service for this account
        for service_id, plan_id in service_plan_pairs:
            service_name = next(
                (s['name'] for s in services["services"]["service"] if int(s['id']) == service_id),
                f"Service-{service_id}"
            )
            
            if activate_service_for_account(account_id, service_id, plan_id, logger):
                successful_operations += 1
                account_successes += 1
                logger.info(f"  ✓ Activated {service_name}")
            else:
                failed_operations += 1
                account_failures += 1
                logger.warning(f"  ✗ Failed to activate {service_name}")
        
        logger.info(f"Account {account_id} complete: {account_successes} successes, {account_failures} failures")
        
        # Progress update every 10 accounts (only for bulk mode)
        if not test_mode and i % 10 == 0:
            completion_percentage = (i / account_count) * 100
            logger.info(f"Progress: {completion_percentage:.1f}% complete ({i}/{account_count} accounts)")
    
    return successful_operations, failed_operations

def validate_service_plan(services: Dict[str, Any], plans: Dict[str, Any], service_id: int, plan_id: int) -> Tuple[bool, str]:
    """Validate that service and plan exist and are compatible."""
    # Check if service exists
    service_exists = any(int(s['id']) == service_id for s in services["services"]["service"])
    if not service_exists:
        return False, f"Service ID {service_id} not found"
    
    # Check if plan exists
    plan_exists = any(int(p['id']) == plan_id for p in plans["plans"]["plan"])
    if not plan_exists:
        return False, f"Plan ID {plan_id} not found"
    
    # Check if plan belongs to service
    plan_service_id = None
    for plan in plans["plans"]["plan"]:
        if int(plan['id']) == plan_id:
            plan_service_id = int(plan['service_id'])
            break
    
    if plan_service_id != service_id:
        return False, f"Plan ID {plan_id} belongs to service {plan_service_id}, not service {service_id}"
    
    return True, "Valid service/plan combination"

def get_service_name(services: Dict[str, Any], service_id: int) -> str:
    """Get service name by ID."""
    for service in services["services"]["service"]:
        if int(service['id']) == service_id:
            return service['name']
    return f"Service-{service_id}"

def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(description="Activate services for 3Scale accounts")
    parser.add_argument("--account-id", type=int, help="Test on a specific account ID only")
    parser.add_argument("--service-id", type=int, help="Activate only this specific service ID")
    parser.add_argument("--plan-id", type=int, help="Use this specific plan ID (required with --service-id)")
    args = parser.parse_args()
    
    # Validate arguments
    if args.service_id and not args.plan_id:
        parser.error("--plan-id is required when using --service-id")
    if args.plan_id and not args.service_id:
        parser.error("--service-id is required when using --plan-id")
    
    logger = setup_logging()
    
    test_mode = args.account_id is not None
    specific_service_mode = args.service_id is not None
    
    # Determine execution mode
    if test_mode and specific_service_mode:
        logger.info(f"TEST MODE: Activating service {args.service_id} (plan {args.plan_id}) for account ID {args.account_id}")
    elif test_mode:
        logger.info(f"TEST MODE: Activating all services for account ID {args.account_id}")
    elif specific_service_mode:
        logger.info(f"SPECIFIC SERVICE MODE: Activating service {args.service_id} (plan {args.plan_id}) for all accounts")
    else:
        logger.info("Starting activation of all services for all accounts")
    
    # Get all accounts
    logger.info("Fetching accounts...")
    accounts = asf.get_accounts()
    all_account_count = len(accounts['accounts']['account'])
    logger.info(f"Found {all_account_count} accounts")
    
    # Filter accounts if testing on specific account
    if test_mode:
        target_account = find_account_by_id(accounts, args.account_id)
        if not target_account:
            logger.error(f"Account ID {args.account_id} not found")
            return 1
        
        accounts_to_process = [target_account]
        logger.info(f"Found target account: {target_account.get('org_name', 'Unknown')} (ID: {args.account_id})")
    else:
        accounts_to_process = accounts["accounts"]["account"]
    
    # Get all services
    logger.info("Fetching services...")
    services = asf.get_services()
    service_count = len(services['services']['service'])
    logger.info(f"Found {service_count} services")
    
    # Get all service plans
    logger.info("Fetching service plans...")
    plans = asf.get_service_plans()
    logger.info(f"Found {len(plans['plans']['plan'])} application plans")
    
    # Handle specific service/plan mode
    if specific_service_mode:
        # Validate the specific service/plan combination
        is_valid, message = validate_service_plan(services, plans, args.service_id, args.plan_id)
        if not is_valid:
            logger.error(f"Invalid service/plan combination: {message}")
            return 1
        
        service_plan_pairs = [(args.service_id, args.plan_id)]
        service_name = get_service_name(services, args.service_id)
        logger.info(f"Validated service/plan: {service_name} (ID: {args.service_id}) with plan {args.plan_id}")
    else:
        # Get all service-plan pairs
        service_plan_pairs = get_all_service_plans(services, plans)
        logger.info(f"Found {len(service_plan_pairs)} service-plan combinations")
    
    # Display services that will be activated
    if specific_service_mode:
        service_name = get_service_name(services, args.service_id)
        logger.info(f"Service to be activated: {service_name} (ID: {args.service_id})")
    else:
        logger.info("Services to be activated:")
        for service in services["services"]["service"]:
            logger.info(f"  - {service['name']} (ID: {service['id']})")
    
    # Calculate total operations
    account_count = len(accounts_to_process)
    total_operations = account_count * len(service_plan_pairs)
    
    # Log operation details
    if test_mode and specific_service_mode:
        logger.info(f"TEST MODE: {total_operations} operations (1 service for 1 account)")
    elif test_mode:
        logger.info(f"TEST MODE: {total_operations} operations for 1 account")
    elif specific_service_mode:
        logger.info(f"SPECIFIC SERVICE MODE: {total_operations} operations (1 service for {account_count} accounts)")
    else:
        logger.info(f"Starting activation process: {total_operations} total operations for {account_count} accounts")
    
    # Process accounts
    successful_operations, failed_operations = process_accounts(
        accounts_to_process, services, service_plan_pairs, logger, test_mode
    )
    
    # Final summary
    logger.info("=" * 50)
    if test_mode and specific_service_mode:
        mode_prefix = "TEST MODE (SPECIFIC SERVICE) "
    elif test_mode:
        mode_prefix = "TEST MODE "
    elif specific_service_mode:
        mode_prefix = "SPECIFIC SERVICE MODE "
    else:
        mode_prefix = ""
    
    logger.info(f"{mode_prefix}ACTIVATION SUMMARY")
    logger.info("=" * 50)
    logger.info(f"Accounts processed: {account_count}")
    
    if specific_service_mode:
        service_name = get_service_name(services, args.service_id)
        logger.info(f"Service activated: {service_name} (ID: {args.service_id})")
        logger.info(f"Plan used: {args.plan_id}")
    else:
        logger.info(f"Total services: {service_count}")
    
    logger.info(f"Total operations: {total_operations}")
    logger.info(f"Successful activations: {successful_operations}")
    logger.info(f"Failed activations: {failed_operations}")
    logger.info(f"Success rate: {(successful_operations/total_operations)*100:.1f}%")
    
    # Test mode feedback
    if test_mode:
        if failed_operations == 0:
            logger.info("✓ TEST PASSED: All services activated successfully!")
            if specific_service_mode:
                logger.info("You can now run without --account-id to apply this service to all accounts.")
            else:
                logger.info("You can now run without --account-id to process all accounts.")
        else:
            logger.warning("✗ TEST ISSUES: Some services failed to activate. Check the log for details.")
    
    if failed_operations > 0:
        logger.warning(f"There were {failed_operations} failures. Check the log for details.")
        return 1
    else:
        if not test_mode:
            logger.info("All services activated successfully!")
        return 0

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)