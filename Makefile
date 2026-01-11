# Makefile for Ravion Modules

.PHONY: help test test-vpc test-alb test-nlb test-sg test-ecs test-elasticache test-cleanup test-cleanup-dry clean fmt validate deps test-single test-ecs-cluster test-ecs-service list-tests

TIMEOUT ?= 60m
PARALLEL ?= 2
TEST_DIR := ./test

help:
	@echo "Usage: make [target] [TIMEOUT=60m] [PARALLEL=2]"
	@echo ""
	@echo "Test Targets:"
	@echo "  test                 Run all integration tests"
	@echo "  test-single          Run a single test (TEST=TestName required)"
	@echo "  test-vpc             Run VPC module tests"
	@echo "  test-alb             Run ALB module tests"
	@echo "  test-nlb             Run NLB module tests"
	@echo "  test-sg              Run Security Group tests"
	@echo "  test-ecs             Run all ECS tests"
	@echo "  test-ecs-cluster     Run ECS Cluster tests"
	@echo "  test-ecs-service     Run ECS Service tests"
	@echo "  test-elasticache     Run ElastiCache tests"
	@echo ""
	@echo "Cleanup Targets:"
	@echo "  test-cleanup         Clean up orphaned test resources"
	@echo "  test-cleanup-dry     Dry run - show what would be cleaned"
	@echo "  clean                Remove test artifacts and state files"
	@echo ""
	@echo "Utility Targets:"
	@echo "  deps                 Download Go dependencies"
	@echo "  fmt                  Format all Terraform files"
	@echo "  validate             Validate all modules"
	@echo "  list-tests           List all available tests"
	@echo ""
	@echo "Examples:"
	@echo "  make test                        # Run all tests"
	@echo "  make test PARALLEL=1             # Run tests sequentially"
	@echo "  make test-vpc TIMEOUT=30m        # Run VPC tests"
	@echo "  make test-single TEST=TestVpcBasic"

deps:
	@echo "Downloading Go dependencies..."
	@cd $(TEST_DIR) && go mod download
	@echo "Dependencies downloaded"

test:
	@echo "Running all tests (timeout=$(TIMEOUT), parallel=$(PARALLEL))..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) ./... 2>&1 | tee test.log

test-single:
ifndef TEST
	$(error TEST is required. Usage: make test-single TEST=TestVpcBasic)
endif
	@echo "Running test: $(TEST)..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -run $(TEST) ./...

test-vpc:
	@echo "Running VPC tests..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) -run TestVpc ./...

test-alb:
	@echo "Running ALB tests..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) -run TestAlb ./...

test-nlb:
	@echo "Running NLB tests..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) -run TestNlb ./...

test-sg:
	@echo "Running Security Group tests..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) -run TestSecurityGroup ./...

test-ecs:
	@echo "Running ECS tests..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) -run TestEcs ./...

test-ecs-cluster:
	@echo "Running ECS Cluster tests..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) -run TestEcsCluster ./...

test-ecs-service:
	@echo "Running ECS Service tests..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) -run TestEcsService ./...

test-elasticache:
	@echo "Running ElastiCache tests..."
	cd $(TEST_DIR) && go test -v -timeout $(TIMEOUT) -parallel $(PARALLEL) -run TestElastiCache ./...

test-cleanup:
	@echo "Cleaning up orphaned terratest resources..."
	cd $(TEST_DIR) && go test -v -timeout 30m -run TestCleanupOrphanedResources ./...

test-cleanup-dry:
	@echo "Dry run: Finding orphaned terratest resources..."
	cd $(TEST_DIR) && go test -v -timeout 30m -run TestCleanupOrphanedResourcesDryRun ./...

fmt:
	@echo "Formatting Terraform files..."
	tofu fmt -recursive
	@echo "Formatting complete"

validate:
	@echo "Validating modules..."
	@for dir in $$(find . -name "*.tf" -exec dirname {} \; | sort -u | grep -v "\.terraform" | grep -v "test/fixtures"); do \
		if [ -f "$$dir/versions.tf" ]; then \
			echo "Validating $$dir..."; \
			(cd "$$dir" && tofu init -backend=false > /dev/null 2>&1 && tofu validate) || exit 1; \
		fi \
	done
	@echo "All modules valid"

clean:
	@echo "Cleaning up test artifacts..."
	rm -f $(TEST_DIR)/test.log
	rm -f $(TEST_DIR)/test-results.json
	find $(TEST_DIR)/fixtures -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find $(TEST_DIR)/fixtures -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	find $(TEST_DIR)/fixtures -name "terraform.tfstate*" -delete 2>/dev/null || true
	@echo "Cleanup complete"

list-tests:
	@echo "Available tests:"
	@cd $(TEST_DIR) && go test -list '.*' ./... 2>/dev/null | grep -E '^Test' | sort
