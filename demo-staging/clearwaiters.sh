#!/bin/bash
gcloud beta runtime-config configs waiters delete c2d-sql-01_waiter  --config-name={deployment-name}-runtime-config
gcloud beta runtime-config configs waiters delete c2d-sql-02_waiter  --config-name={deployment-name}-runtime-config
gcloud beta runtime-config configs waiters delete c2d-sql-03_waiter  --config-name={deployment-name}-runtime-config
