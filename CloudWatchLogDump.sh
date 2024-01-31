#!/bin/bash

usage() {
	echo "$0"
	echo " Script to fetch logs from CloudWatch Logs"
	echo "------------------------------------------"
	echo " List logs group:"
	echo " Usage: $0 ls -p <PROFILE>"
	echo "------------------------------------------"
	echo " List logs stream from a log group:"
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
	echo " -h | --help                              Display this help message"
	exit 1
}

if [ $# -eq 0 ]; then
	usage
fi

while [ "$1" != "" ]; do
	case $1 in
	-l | --log-group-name)
		shift
		LOG_GROUP_NAME=$1
		;;
	-p | --profile)
		shift
		PROFILE=$1
		;;
	-f | --filter-pattern)
		shift
		FILTER_PATTERN=$1
		;;
	-m | --max-iterations)
		shift
		MAX_ITERATIONS=$1
		;;
	-s | --log-stream-name)
		shift
		LOG_STREAM_NAME=$1
		;;
	ls)
		LIST_LOG_GROUPS=true
		;;
	-o)
		OUTPUT_FLAG=true
		;;
	--start-date)
		shift
		START_DATE=$1
		;;
	--start-time)
		shift
		START_TIME=$1
		;;
	--end-date)
		shift
		END_DATE=$1
		;;
	--end-time)
		shift
		END_TIME=$1
		;;
	--show-err)
		IS_SHOW_ERR=true
		;;
	--tail)
		TAIL=true
		;;
	--debug)
		set -x
		DEBUG=true
		;;
	-h | --help)
		usage
		;;
	*)
		usage
		;;
	esac
	shift
done

if [ -n "$START_DATE" ] || [ -n "$START_TIME" ]; then
	IS_USE_START_TIME=true
fi

if [ -n "$END_DATE" ] || [ -n "$END_TIME" ]; then
	IS_USE_END_TIME=true
fi

if [ -z "$START_DATE" ]; then
	START_DATE=$(date +%Y-%m-%d)
fi

if [ -z "$START_TIME" ]; then
	START_TIME="00:00:00"
fi

if [ -z "$END_DATE" ]; then
	END_DATE=$START_DATE
fi

if [ -z "$END_TIME" ]; then
	END_TIME="23:59:59"
fi

if [[ "$IS_USE_START_TIME" = true ]] && [[ "$IS_USE_END_TIME" = true ]]; then
	if [[ "$START_DATE $START_TIME" > "$END_DATE $END_TIME" ]]; then
		echo "Start date/time must be before end date/time"
		exit 1
	fi
fi

if [[ "$IS_USE_START_TIME" = true ]]; then
	START_TIME_MS="--start-time $(date -d "$START_DATE $START_TIME" +%s%3N)"
else
	START_TIME_MS=""
fi

if [[ "$IS_USE_END_TIME" = true ]]; then
	END_TIME_MS="--end-time $(date -d "$END_DATE $END_TIME" +%s%3N)"
else
	END_TIME_MS=""
fi

if [ -z "$IS_SHOW_ERR" ]; then
	IS_SHOW_ERR=false
fi
SHOW_ERR=$([[ "$IS_SHOW_ERR" != true ]] && echo "2>/dev/null" || echo "")

if [ -z "$HEAD" ]; then
	HEAD=0
fi

if [ -z "$TAIL" ]; then
	TAIL=false
fi

if [[ "$TAIL" != true ]]; then
	HEAD="--start-from-head"
else
	HEAD=""
fi

if [ -z "$MAX_ITERATIONS" ]; then
	MAX_ITERATIONS=1
fi

if [ -n "$MAX_ITERATIONS" ] && [ "$MAX_ITERATIONS" -eq "$MAX_ITERATIONS" ] 2>/dev/null; then
	# printf "# CloudWatchLogDump\n"
	echo ""
else
	echo "MAX_ITERATIONS must be an integer"
	exit 1
fi

if [ -z "$FILTER_PATTERN" ]; then
	FILTER_PATTERN=""
fi

listLogsGroup() {
	base_cmd="aws logs describe-log-groups --profile \"$PROFILE\""
	logs=$(eval "$base_cmd" "$SHOW_ERR" | jq -r '.logGroups[] | .logGroupName')

	readarray -t log_groups <<<"$logs"
	declare -a numbered_log_groups

	for i in "${!log_groups[@]}"; do
		numbered_log_groups+=("#$((i + 1)) ${log_groups[$i]}")
		echo "${numbered_log_groups[$i]}"
	done

}

if [ "$LIST_LOG_GROUPS" = true ]; then
	listLogsGroup
	exit 0
fi

if [ -n "$DEBUG" ]; then
	echo "LOG_GROUP_NAME = $LOG_GROUP_NAME"
	echo "LOG_STREAM_NAME = $LOG_STREAM_NAME"
	echo "FILTER_PATTERN = $FILTER_PATTERN"
	echo "MAX_ITERATIONS = $MAX_ITERATIONS"
	echo "START_DATE = $START_DATE"
	echo "START_TIME = $START_TIME"
	echo "END_DATE = $END_DATE"
	echo "END_TIME = $END_TIME"
	echo "PROFILE = $PROFILE"
fi

fetchLogs() {
	LOG_STREAM=$1
	echo "###################################################"
	echo "Fetching logs for $LOG_STREAM ..."
	echo "###################################################"

	current_time_ms=$(date +%s%3N)
	# TODO: make this configurable
	within_time_ms=$((5 * 60 * 1000))

	fetchLogsStream="aws logs get-log-events --log-group-name \$LOG_GROUP_NAME --log-stream-name \$LOG_STREAM --profile \$PROFILE"
	base_cmd="$fetchLogsStream $HEAD $START_TIME_MS $END_TIME_MS $SHOW_ERR"
	OUTPUT=$(eval "$base_cmd" | jq)
	IS_EVENT=$(echo "$OUTPUT" | jq -r '.events[]')
	FORWARD_TOKEN=$(echo "$OUTPUT" | jq -r '.nextForwardToken')
	NEXT_FORWARD_TOKEN=""
	if [[ "$IS_EVENT" != "" ]] && [[ "$FORWARD_TOKEN" != "" ]]; then
		echo "$OUTPUT" | jq -r '.events[] | .message' | jq '.log' -r

		while true; do
			base_cmd="$fetchLogsStream $HEAD --next-token $FORWARD_TOKEN $START_TIME_MS $END_TIME_MS $SHOW_ERR"
			OUTPUT=$(eval "$base_cmd" | jq)
			IS_EVENT=$(echo "$OUTPUT" | jq -r '.events[]')
			NEXT_FORWARD_TOKEN=$(echo "$OUTPUT" | jq -r '.nextForwardToken')

			last_log_timestamp=$(echo "$OUTPUT" | jq -r '.events[-1].timestamp')
			time_diff_ms=$((current_time_ms - last_log_timestamp))

			if [[ "$time_diff_ms" -le "$within_time_ms" ]]; then
				echo "--------------------------------------------------"
				with_in_time="$((within_time_ms / 1000 / 60))"
				echo "Stop: Logs are within $with_in_time minutes of the current time."
				break
			fi

			if [[ $FORWARD_TOKEN == "$NEXT_FORWARD_TOKEN" ]]; then
				echo "--------------------------------------------------"
				echo "No more events found for $LOG_STREAM"
				break
			fi

			if [[ "$IS_EVENT" != "" ]] && [[ "$FORWARD_TOKEN" != "" ]]; then
				echo "$OUTPUT" | jq -r '.events[] | .message' | jq '.log' -r
				FORWARD_TOKEN="$NEXT_FORWARD_TOKEN"
			fi

			if [[ "$IS_EVENT" == "" ]] && [[ "$FORWARD_TOKEN" != "" ]]; then
				echo "--------------------------------------------------"
				echo "No more events found for $LOG_STREAM"
				break
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

for ((iteration_count = 1; iteration_count <= MAX_ITERATIONS; iteration_count++)); do
	echo "Fetching logs, iteration $iteration_count ..."
	base_cmd="aws logs describe-log-streams --log-group-name \"$LOG_GROUP_NAME\" --order-by \"LastEventTime\" --descending --query \"{logStreams:logStreams[?contains(logStreamName, '$FILTER_PATTERN') == \\\`true\\\`].{logStreamName:logStreamName,firstEventTimestamp:firstEventTimestamp,lastEventTimestamp:lastEventTimestamp}, nextToken: nextToken}\" --limit 50 --profile \"$PROFILE\""

	if [ -z "$next_token" ]; then
		logs=$(eval "$base_cmd" "$SHOW_ERR" | jq)
	else
		logs=$(eval "$base_cmd" "--next-token" "$next_token" "$SHOW_ERR" | jq)
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
	done <<<"$log_streams_json"
done
echo "---------------------------------------------------"
echo "## log_streams_info length: ${#log_streams_info[@]}"
echo "---------------------------------------------------"
for element in "${log_streams_info[@]}"; do
	eval "declare -A log_stream=""${element#*=}"
	first_event_timestamp_s=$((log_stream[firstEventTimestamp] / 1000))
	last_event_timestamp_s=$((log_stream[lastEventTimestamp] / 1000))
	echo "Log Stream Name       : ${log_stream[name]}"
	echo "First Event Timestamp : $(date -d @$first_event_timestamp_s +'%Y-%m-%d %H:%M:%S')"
	echo "Last Event Timestamp  : $(date -d @$last_event_timestamp_s +'%Y-%m-%d %H:%M:%S')"
	echo "---------------------------------------------------"
done

if [ "$OUTPUT_FLAG" = true ]; then
	for log_stream in "${log_streams_info[@]}"; do
		fetchLogs "${log_stream[name]}"
	done
fi
