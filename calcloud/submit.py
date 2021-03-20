"""This module supports submitting job plan tuples to AWS Batch for processing."""

import sys
import ast

import boto3

from . import plan
from . import common


def submit_job(plan_tuple):
    """Given a job description `plan_tuple` from the planner,  submit a job to AWS batch."""
    info = plan.Plan(*plan_tuple)
    job = {
        "jobName": info.job_name,
        "jobQueue": info.job_queue,
        "jobDefinition": info.job_definition,
        "containerOverrides": {
            # "resourceRequirements": [
            #     {"value": f"{info.memory}", "type": "MEMORY"},
            #     {"value": f"{info.vcpus}", "type": "VCPU"},
            # ],
            "command": [info.command, info.ipppssoot, info.input_path, info.s3_output_uri, info.crds_config],
        },
        "timeout": {"attemptDurationSeconds": info.max_seconds,},
    }
    client = boto3.client("batch", config=common.retry_config)
    return client.submit_job(**job)


def submit_plans(plan_file):
    """Given a file `plan_file` defining job plan tuples one-per-line,
    submit each job and output the plan and submission response to stdout.
    Plans are generated by the calcloud.plan module.
    """
    if plan_file == "-":
        f = sys.stdin
    else:
        f = open(plan_file)
    for line in f.readlines():
        job_plan = ast.literal_eval(line)
        print(submit_job(job_plan))


if __name__ == "__main__":
    if len(sys.argv) == 2:
        submit_plans(sys.argv[1])
    else:
        print("usage:  python -m calcloud.submit [<plan_file> | - ]", file=sys.stderr)
