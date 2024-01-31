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
	# -F | --config-file)
	# 	shift
	# 	CONFIG_FILE=$1
	# 	TARGET=$(echo "$CONFIG_FILE" | cut -d'=' -f2)
	# 	CONFIG_FILE=$(echo "$CONFIG_FILE" | cut -d'=' -f1)
	# 	if [ "$TARGET" == "$CONFIG_FILE" ]; then
	# 		TARGET="default"
	# 	fi
	# 	;;
	-m | --max-iterations)
		shift
		MAX_ITERATIONS=$1
		;;
	-s | --log-stream-name)
		shift
		LOG_STREAM_NAME=$1
		;;
	--head)
		shift
		HEAD=$1
		;;
	--tail)
		shift
		TAIL=$1
		;;
	ls)
		LIST_LOG_GROUPS=true
		;;
	-o)
		OUTPUT_FLAG=true
		;;
	--show-err)
		IS_SHOW_ERR=true
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

read_ini() {
	local section=$1
	local key=$2
	local default=$3
	local awk_script
	local value

	awk_script="/$section/ {found=1} found && /$key/ {print \$2; exit}"
	value=$(awk -F '=' "$awk_script" "$CONFIG_FILE" | sed 's/^[ \t]*//;s/[ \t]*$//')

	if [ -z "$value" ] && [ -n "$default" ]; then
		echo "$default"
	else
		echo "$value"
	fi
}

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
	PROFILE=$([[ -n "$PROFILE" ]] && echo "$PROFILE" || echo "$(read_ini "$TARGET" PROFILE "$(read_ini default PROFILE)")")
	LOG_GROUP_NAME=$([[ -n "$LOG_GROUP_NAME" ]] && echo "$LOG_GROUP_NAME" || echo "$(read_ini "$TARGET" LOG_GROUP_NAME "$(read_ini default LOG_GROUP_NAME)")")
	LOG_STREAM_NAME=$([[ -n "$LOG_STREAM_NAME" ]] && echo "$LOG_STREAM_NAME" || echo "$(read_ini "$TARGET" LOG_STREAM_NAME "$(read_ini default LOG_STREAM_NAME)")")
	FILTER_PATTERN=$([[ -n "$FILTER_PATTERN" ]] && echo "$FILTER_PATTERN" || echo "$(read_ini "$TARGET" FILTER_PATTERN "$(read_ini default FILTER_PATTERN)")")
	MAX_ITERATIONS=$([[ -n "$MAX_ITERATIONS" ]] && echo "$MAX_ITERATIONS" || echo "$(read_ini "$TARGET" MAX_ITERATIONS "$(read_ini default MAX_ITERATIONS)")")
	IS_SHOW_ERR=$([[ -n "$IS_SHOW_ERR" ]] && echo "$IS_SHOW_ERR" || echo "$(read_ini "$TARGET" IS_SHOW_ERR "$(read_ini default IS_SHOW_ERR)")")
	OUTPUT_FLAG=$([[ -n "$OUTPUT_FLAG" ]] && echo "$OUTPUT_FLAG" || echo "$(read_ini "$TARGET" OUTPUT_FLAG "$(read_ini default OUTPUT_FLAG)")")
	LIST_LOG_GROUPS=$([[ -n "$LIST_LOG_GROUPS" ]] && echo "$LIST_LOG_GROUPS" || echo "$(read_ini "$TARGET" LIST_LOG_GROUPS "$(read_ini default LIST_LOG_GROUPS)")")
	HEAD=$([[ -n "$HEAD" ]] && echo "$HEAD" || echo "$(read_ini "$TARGET" HEAD "$(read_ini default HEAD)")")
	TAIL=$([[ -n "$TAIL" ]] && echo "$TAIL" || echo "$(read_ini "$TARGET" TAIL "$(read_ini default TAIL)")")

	echo "PROFILE = $PROFILE"
	echo "LOG_GROUP_NAME = $LOG_GROUP_NAME"
	echo "LOG_STREAM_NAME = $LOG_STREAM_NAME"
	echo "FILTER_PATTERN = $FILTER_PATTERN"
	echo "MAX_ITERATIONS = $MAX_ITERATIONS"
elif [ -n "$CONFIG_FILE" ] && [ ! -f "$CONFIG_FILE" ]; then
	echo "File '$CONFIG_FILE' does not exist."
	exit 1
fi

if [ -z "$IS_SHOW_ERR" ]; then
	IS_SHOW_ERR=false
fi
SHOW_ERR=$([[ "$IS_SHOW_ERR" != true ]] && echo "2>/dev/null" || echo "")

if [ -z "$HEAD" ]; then
	HEAD=0
fi

if [ -z "$TAIL" ]; then
	TAIL=0
fi

if [ -z "$MAX_ITERATIONS" ]; then
	MAX_ITERATIONS=1
fi

if [ -n "$MAX_ITERATIONS" ] && [ "$MAX_ITERATIONS" -eq "$MAX_ITERATIONS" ] 2>/dev/null; then
	printf "# CloudWatchLogDump\n"
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
	echo "$logs"
}

if [ "$LIST_LOG_GROUPS" = true ]; then
	listLogsGroup
	exit 0
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
	base_cmd="$fetchLogsStream --start-from-head $SHOW_ERR"
	OUTPUT=$(eval "$base_cmd" | jq)
	IS_EVENT=$(echo "$OUTPUT" | jq -r '.events[]')
	FORWARD_TOKEN=$(echo "$OUTPUT" | jq -r '.nextForwardToken')
	NEXT_FORWARD_TOKEN=""
	if [[ "$IS_EVENT" != "" ]] && [[ "$FORWARD_TOKEN" != "" ]]; then
		echo "$OUTPUT" | jq -r '.events[] | .message' | jq '.log' -r

		while true; do
			base_cmd="$fetchLogsStream --start-from-head --next-token $FORWARD_TOKEN $SHOW_ERR"
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
