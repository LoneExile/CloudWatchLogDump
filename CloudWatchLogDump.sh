#!/bin/bash

usage() {
    echo " Script to fetch logs from CloudWatch Logs"
    echo "------------------------------------------"
    echo " Fetch logs from a log group:"
    echo " Usage: $0 -l <LOG_GROUP_NAME> -f <FILTER_PATTERN> -m <MAX_ITERATIONS> -p <PROFILE> [-o]"
    echo "  -l | --log-group-name <LOG_GROUP_NAME>  Log group name to fetch logs from"
    echo "  -f | --filter-pattern <FILTER_PATTERN>  Filter pattern to use when fetching log streams (default: \"\" )"
    echo "  -m | --max-iterations <MAX_ITERATIONS>  Maximum number of iterations*50 to fetch log streams (default: 1)"
    echo "  -p | --profile <PROFILE>                AWS profile to use (default: \"\" )"
    echo "  -o                                      Option flag to fetch the log output (default: false)"
    echo "------------------------------------------"
    echo " Fetch logs from a log stream:"
    echo " Usage: $0 -l <LOG_GROUP_NAME> -s <LOG_STREAM_NAME> -p <PROFILE>"
    echo "  -s | --log-stream-name <LOG_STREAM_NAME> Log stream name to fetch logs from"
    echo "------------------------------------------"
    echo "  -h | --help                             Display this help message"
    exit 1
}

if [ $# -eq 0 ]; then
    usage
fi

while [ "$1" != "" ]; do
    case $1 in
        -l | --log-group-name ) shift
            LOG_GROUP_NAME=$1
            ;;
        -p | --profile )        shift
            PROFILE=$1
            ;;
        -f | --filter-pattern ) shift
            FILTER_PATTERN=$1
            ;;
        -m | --max-iterations ) shift
            MAX_ITERATIONS=$1
            ;;
        -s | --log-stream-name ) shift
            LOG_STREAM_NAME=$1
            ;;
        -o )                    OPTION_FLAG=true
            ;;
        -h | --help )           usage
            ;;
        * )                     usage
            ;;
    esac
    shift
done

if [ -z "$MAX_ITERATIONS" ]; then
    MAX_ITERATIONS=1
fi

if [ -n "$MAX_ITERATIONS" ] && [ "$MAX_ITERATIONS" -eq "$MAX_ITERATIONS" ] 2>/dev/null; then
    echo "MAX_ITERATIONS: $MAX_ITERATIONS"
else
    echo "MAX_ITERATIONS must be an integer"
    exit 1
fi

if [ -z "$FILTER_PATTERN" ]; then
    FILTER_PATTERN=""
fi

fetchLogsStream='aws logs get-log-events --log-group-name "$LOG_GROUP_NAME" --log-stream-name "$LOG_STREAM" --profile "$PROFILE"'

fetchLogs() {
    LOG_STREAM=$1
    echo "###################################################"
    echo  Fetching logs for "$LOG_STREAM" ...
    echo "###################################################"

    ## TODO: add flag --start-from-head
    OUTPUT=$(eval "$fetchLogsStream" "--start-from-head" "2>/dev/null" | jq )
    IS_EVENT=$(echo "$OUTPUT" | jq -r '.events[]')
    FORWARD_TOKEN=$(echo "$OUTPUT" | jq -r '.nextForwardToken')
    NEXT_FORWARD_TOKEN=""
    if [[ "$IS_EVENT" != "" ]] && [[ "$FORWARD_TOKEN" != "" ]]; then
        echo "$OUTPUT" | jq -r '.events[] | .message' | jq '.log' -r

        while true
        do
            OUTPUT=$(eval "$fetchLogsStream" "--start-from-head" "--next-token" "$FORWARD_TOKEN" "2>/dev/null" | jq )
            IS_EVENT=$(echo "$OUTPUT" | jq -r '.events[]')
            NEXT_FORWARD_TOKEN=$(echo "$OUTPUT" | jq -r '.nextForwardToken')
            echo "$NEXT_FORWARD_TOKEN"
            echo "$FORWARD_TOKEN"

            if [[ $FORWARD_TOKEN == "$NEXT_FORWARD_TOKEN" ]]; then
                echo "--------------------------------------------------"
                echo "No more events found for $LOG_STREAM"
                break
            fi

            if [[ "$IS_EVENT" != "" ]] && [[ "$FORWARD_TOKEN" != "" ]]; then
                echo "$OUTPUT" | jq -r '.events[] | .message' | jq '.log' -r
                FORWARD_TOKEN="$NEXT_FORWARD_TOKEN"
            fi
        done
    else
        echo "No events found or unable to fetch events for $LOG_STREAM"
    fi
}

if [ -n "$LOG_STREAM_NAME" ] && [ -n "$LOG_GROUP_NAME" ]; then
    fetchLogs "$LOG_STREAM_NAME"
    exit 0
fi

if [ -z "$MAX_ITERATIONS" ] || [ -z "$LOG_GROUP_NAME" ]; then
    usage
fi

declare -a log_streams_info
declare -A log_stream
next_token=""

for (( iteration_count=1; iteration_count<=MAX_ITERATIONS; iteration_count++ )); do
    echo "Fetching logs, iteration $iteration_count ..."
    if [ -z "$next_token" ]; then
        logs=$(aws logs describe-log-streams --log-group-name "$LOG_GROUP_NAME" --order-by "LastEventTime" --descending --query "{logStreams:logStreams[?contains(logStreamName, '$FILTER_PATTERN') == \`true\`].{logStreamName:logStreamName,firstEventTimestamp:firstEventTimestamp,lastEventTimestamp:lastEventTimestamp}, nextToken: nextToken}" --limit 50 --profile "$PROFILE" 2>/dev/null | jq)
    else
        logs=$(aws logs describe-log-streams --next-token "$next_token" --log-group-name "$LOG_GROUP_NAME" --order-by "LastEventTime" --descending --query "{logStreams:logStreams[?contains(logStreamName, '$FILTER_PATTERN') == \`true\`].{logStreamName:logStreamName,firstEventTimestamp:firstEventTimestamp,lastEventTimestamp:lastEventTimestamp}, nextToken: nextToken}" --limit 50 --profile "$PROFILE" 2>/dev/null | jq)
    fi

    log_streams_json=$(echo "$logs" | jq -c '.logStreams[]')
    next_token=$(echo "$logs" | jq -r '.nextToken')

    if [ -z "$log_streams_json" ]; then
        continue
    fi

    while read -r log_stream_json; do
        log_stream_name=$(echo "$log_stream_json" | jq -r '.logStreamName')
        first_event_timestamp=$(echo "$log_stream_json" | jq -r '.firstEventTimestamp')
        last_event_timestamp=$(echo "$log_stream_json" | jq -r '.lastEventTimestamp')

        log_stream=([name]="$log_stream_name" [firstEventTimestamp]="$first_event_timestamp" [lastEventTimestamp]="$last_event_timestamp")
        log_streams_info+=("$(declare -p log_stream)")
    done <<< "$log_streams_json"

    echo "---------------------------------------------------"
done

echo "log_streams_info length: ${#log_streams_info[@]}"
for element in "${log_streams_info[@]}"; do
    firstEventTimestamp_s=$((log_stream[firstEventTimestamp]/1000))
    lastEventTimestamp_s=$((log_stream[lastEventTimestamp]/1000))
    eval "declare -A log_stream=""${element#*=}"
    echo "Log Stream Name: ${log_stream[name]}"
    echo "First Event Timestamp: $(date -d @$firstEventTimestamp_s +'%Y-%m-%d %H:%M:%S')"
    echo "Last Event Timestamp: $(date -d @$lastEventTimestamp_s +'%Y-%m-%d %H:%M:%S')"
    echo "---------------------------------------------------"
done

if [ "$OPTION_FLAG" = true ] ; then
    for log_stream in "${log_streams_info[@]}"; do
        fetchLogs "${log_stream[name]}"
    done
fi
