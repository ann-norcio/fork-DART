# Github Action: Build Everything On Demand GitHub

This is an on-demand GitHub action version of the 'build_everything' developer test.

## Description

When this action is triggered, it will:
1. Checkout DART
2. Create an mkmf.template for gfortran only
3. Run fixsystem
4. mondify input.nml files to avoid race conditions
5. Run all quickbuild.sh scripts and report failures

## How to Run the Action

1. Via GitHub UI:
   - Go to the "Actions" tab in the DART repo
   - Navigate to the "Build Everything On Demand" workflow and click "Run workflow"
     
2. Via GitHub CLI:
   - Run "gh workflow run build-everything-on-demand.yml"
