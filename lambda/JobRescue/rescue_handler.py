from calcloud import io
from calcloud import hst

# XXXXX TODO add memory adjustments based on CONTROL folder and
# ipppssoot.
#
# jobId initial memory allocation should be stored here during
# submission, each subsequent run should increment the retry count
# during rescue which implies required memory when the job is
# re-submitted after placing.
#
# The rescue function should use the job ID to search for job failure
# status and conditionally adjust memory if applicable.

RESCUE_TYPES = ["error", "terminated"]


def lambda_handler(event, context):

    try:
        # Decode the S3 event message generated by the message write operation.
        # See S3 docs: https://docs.aws.amazon.com/AmazonS3/latest/userguide/notification-content-structure.html
        bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
        message = event["Records"][0]["s3"]["object"]["key"]
        ipst = message.split("-")[-1]
        # rescue_reason = f"operator posted {message} message"
        print(f"received {message} on bucket s3://{bucket_name}")
        assert hst.IPPPSSOOT_RE.match(ipst) or ipst == "all", "Bad ipppssoot value: " + repr(ipst)
    except Exception as exc:
        return dict(statusCode=400, body="Rescue bad inputs exception: '{str(exc)}'")

    try:
        messages = io.get_message_api(bucket_name)
        inputs = io.get_input_api(bucket_name)
        outputs = io.get_output_api(bucket_name)

        if ipst == "all":
            fail_ipsts = set()
            for type in RESCUE_TYPES:
                ipsts = [msg.split("-")[-1] for msg in messages.list(f"{type}-all")]
                fail_ipsts |= ipsts
            for this in fail_ipsts:
                messages.put(f"rescue-{this}")
            messages.delete("rescue-all")
        else:
            outputs.delete(ipst)
            messages.delete(f"all-{ipst}")
            if inputs.listl(ipst):
                messages.put(f"placed-{ipst}")
        return dict(statusCode=200, body=f"Rescue succeeded/delegated for ipppssoot '{ipst}'")
    except Exception as exc:
        return dict(statusCode=500, body=f"Rescue failed for ipppssoot '{ipst}' with exception: {str(exc)}")