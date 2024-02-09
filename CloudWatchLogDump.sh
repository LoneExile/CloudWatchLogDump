#!/usr/bin/env bash

check_requirements() {
	command -v aws >/dev/null 2>&1 || {
		echo >&2 "AWS CLI is required but it's not installed. Aborting."
		exit 1
	}
	command -v jq >/dev/null 2>&1 || {
		echo >&2 "JQ is required but it's not installed. Aborting."
		exit 1
	}
}

check_requirements

usage() {
	cat <<EOF
Usage: $0 [OPTIONS] [COMMANDS]

Script to fetch logs from AWS CloudWatch Logs.

COMMANDS:
  ls                            List log groups.
  -l, --log-group-name          Specify log group name to fetch logs from.
  -s, --log-stream-name         Specify log stream name to fetch logs from.
  -F, --config-file             Use a config file to specify parameters.
  -h, --help                    Display this help message.

OPTIONS:
  -p, --profile <PROFILE>       AWS profile to use for commands.
  -f, --filter-pattern <PATTERN> Filter pattern for fetching log streams.
	-m, --max-iterations <NUMBER> Max iterations for fetching log streams ( 1 = 50 log streams).

EXAMPLES:
  List log groups:
    $0 ls -p <PROFILE>

  List log streams from a log group:
    $0 -l <LOG_GROUP_NAME> -f <FILTER_PATTERN> -m <MAX_ITERATIONS> -p <PROFILE>

  Fetch logs from a log stream:
    $0 -l <LOG_GROUP_NAME> -s <LOG_STREAM_NAME> -p <PROFILE>

  Fetch logs from a log stream using a config file:
    $0 -F <CONFIG_FILE>  # Format: <CONFIG_FILE>=<TARGET>, e.g., config.ini=default
EOF
	exit 1
}

if [ $# -eq 0 ]; then
	INTERACTIVE_MODE=true
fi

while [ "$1" != "" ]; do
	case $1 in
	ls)
		LIST_LOG_GROUPS=true
		;;
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
	-F | --config-file)
		shift
		CONFIG_FILE=$1
		TARGET=$(echo "$CONFIG_FILE" | cut -d'=' -f2)
		CONFIG_FILE=$(echo "$CONFIG_FILE" | cut -d'=' -f1)
		if [ "$TARGET" == "$CONFIG_FILE" ]; then
			TARGET="default"
		fi
		;;
	-m | --max-iterations)
		shift
		MAX_ITERATIONS=$1
		;;
	-s | --log-stream-name)
		shift
		LOG_STREAM_NAME=$1
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

if [ -z "$IS_SHOW_ERR" ]; then
	IS_SHOW_ERR=false
fi
SHOW_ERR=$([[ "$IS_SHOW_ERR" != true ]] && echo "2>/dev/null" || echo "")

ask_for_profile() {
	echo "Fetching AWS profiles..."
	local cmd="aws configure list-profiles $SHOW_ERR"
	readarray -t profiles < <(eval "$cmd")
	local profile_count=${#profiles[@]}

	echo "Please select an AWS Profile (press Enter to leave as default):"
	for i in "${!profiles[@]}"; do
		echo "$((i + 1))) ${profiles[$i]}"
	done
	echo "Press Enter to leave as default."

	while true; do
		echo ""
		read -r -p "Enter selection (1-${profile_count}): " selection
		if [[ -z "$selection" ]]; then
			echo "Leaving AWS Profile as default."
			PROFILE=""
			break
		elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$profile_count" ]; then
			PROFILE="${profiles[$((selection - 1))]}"
			echo "You selected '$PROFILE'"
			break
		else
			echo "Invalid selection. Please try again or press Enter to leave as default."
		fi
	done
}

ask_for_log_group() {
	echo "Fetching log groups..."
	local cmd="aws logs describe-log-groups --profile \"$PROFILE\" $SHOW_ERR"
	readarray -t log_groups < <(eval "$cmd" | jq -r '.logGroups[] | .logGroupName')

	printf "Please select a log group:"
	for i in "${!log_groups[@]}"; do
		echo "$((i + 1))) ${log_groups[$i]}"
	done

	while true; do
		echo ""
		read -r -p "Enter selection (1-${#log_groups[@]}): " selection
		if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#log_groups[@]}" ]; then
			LOG_GROUP_NAME="${log_groups[$((selection - 1))]}"
			echo "You selected '$LOG_GROUP_NAME'"
			break
		else
			echo "Invalid selection. Please try again or press Enter to leave as default."
		fi
	done
}

ask_for_filter_pattern() {
	echo ""
	printf "Please enter a filter pattern (press Enter to leave as default): "
	read -r FILTER_PATTERN
	if [[ -z "$FILTER_PATTERN" ]]; then
		echo "Leaving filter pattern as default."
	else
		echo "You entered '$FILTER_PATTERN'"
	fi
}

ask_for_log_steam() {
	echo "Fetching log streams..."
	local cmd="aws logs describe-log-streams --log-group-name \"$LOG_GROUP_NAME\" --order-by \"LastEventTime\" --descending --query \"{logStreams:logStreams[?contains(logStreamName, '$FILTER_PATTERN') == \\\`true\\\`].{logStreamName:logStreamName,firstEventTimestamp:firstEventTimestamp,lastEventTimestamp:lastEventTimestamp}, nextToken: nextToken}\" --limit 50 --profile \"$PROFILE\" $SHOW_ERR"
	readarray -t log_streams < <(eval "$cmd" | jq -r '.logStreams[] | .logStreamName')

	echo "Please select a log stream:"
	for i in "${!log_streams[@]}"; do
		echo "$((i + 1))) ${log_streams[$i]}"
	done

	while true; do
		echo ""
		read -r -p "Enter selection (1-${#log_streams[@]}): " selection
		if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#log_streams[@]}" ]; then
			LOG_STREAM_NAME="${log_streams[$((selection - 1))]}"
			echo "You selected '$LOG_STREAM_NAME'"
			break
		else
			echo "Invalid selection. Please try again or press Enter to leave as default."
		fi
	done
}

ask_for_start_date() {
	echo ""
	echo "Please enter a start date (YYYY-MM-DD) (press Enter to leave as default):"
	read -r START_DATE
	if [[ -z "$START_DATE" ]]; then
		echo "Leaving start date as default."
	else
		echo "You entered '$START_DATE'"
	fi
}

ask_for_start_time() {
	echo ""
	echo "Please enter a start time (HH:MM:SS) (press Enter to leave as default):"
	read -r START_TIME
	if [[ -z "$START_TIME" ]]; then
		echo "Leaving start time as default."
	else
		echo "You entered '$START_TIME'"
	fi
}

if [[ "$INTERACTIVE_MODE" = true ]]; then
	if [ -z "$PROFILE" ]; then
		ask_for_profile
	fi
	if [ -z "$LOG_GROUP_NAME" ]; then
		ask_for_log_group
	fi
	if [ -z "$FILTER_PATTERN" ]; then
		ask_for_filter_pattern
	fi
	if [ -z "$LOG_STREAM_NAME" ]; then
		ask_for_log_steam
	fi
	if [ -z "$START_DATE" ]; then
		ask_for_start_date
	fi
	if [ -z "$START_TIME" ]; then
		ask_for_start_time
	fi
	echo ""
	echo "---"
	echo "PROFILE = $PROFILE"
	echo "LOG_GROUP_NAME = $LOG_GROUP_NAME"
	echo "FILTER_PATTERN = $FILTER_PATTERN"
	echo "LOG_STREAM_NAME = $LOG_STREAM_NAME"
	echo "START_DATE = $START_DATE"
	echo "START_TIME = $START_TIME"
	echo "---"
fi

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
	LIST_LOG_GROUPS=$([[ -n "$LIST_LOG_GROUPS" ]] && echo "$LIST_LOG_GROUPS" || echo "$(read_ini "$TARGET" LIST_LOG_GROUPS "$(read_ini default LIST_LOG_GROUPS)")")
	LOG_GROUP_NAME=$([[ -n "$LOG_GROUP_NAME" ]] && echo "$LOG_GROUP_NAME" || echo "$(read_ini "$TARGET" LOG_GROUP_NAME "$(read_ini default LOG_GROUP_NAME)")")
	PROFILE=$([[ -n "$PROFILE" ]] && echo "$PROFILE" || echo "$(read_ini "$TARGET" PROFILE "$(read_ini default PROFILE)")")
	FILTER_PATTERN=$([[ -n "$FILTER_PATTERN" ]] && echo "$FILTER_PATTERN" || echo "$(read_ini "$TARGET" FILTER_PATTERN "$(read_ini default FILTER_PATTERN)")")
	MAX_ITERATIONS=$([[ -n "$MAX_ITERATIONS" ]] && echo "$MAX_ITERATIONS" || echo "$(read_ini "$TARGET" MAX_ITERATIONS "$(read_ini default MAX_ITERATIONS)")")
	LOG_STREAM_NAME=$([[ -n "$LOG_STREAM_NAME" ]] && echo "$LOG_STREAM_NAME" || echo "$(read_ini "$TARGET" LOG_STREAM_NAME "$(read_ini default LOG_STREAM_NAME)")")
	OUTPUT_FLAG=$([[ -n "$OUTPUT_FLAG" ]] && echo "$OUTPUT_FLAG" || echo "$(read_ini "$TARGET" OUTPUT_FLAG "$(read_ini default OUTPUT_FLAG)")")
	START_DATE=$([[ -n "$START_DATE" ]] && echo "$START_DATE" || echo "$(read_ini "$TARGET" START_DATE "$(read_ini default START_DATE)")")
	START_TIME=$([[ -n "$START_TIME" ]] && echo "$START_TIME" || echo "$(read_ini "$TARGET" START_TIME "$(read_ini default START_TIME)")")
	END_DATE=$([[ -n "$END_DATE" ]] && echo "$END_DATE" || echo "$(read_ini "$TARGET" END_DATE "$(read_ini default END_DATE)")")
	END_TIME=$([[ -n "$END_TIME" ]] && echo "$END_TIME" || echo "$(read_ini "$TARGET" END_TIME "$(read_ini default END_TIME)")")
	IS_SHOW_ERR=$([[ -n "$IS_SHOW_ERR" ]] && echo "$IS_SHOW_ERR" || echo "$(read_ini "$TARGET" IS_SHOW_ERR "$(read_ini default IS_SHOW_ERR)")")
	TAIL=$([[ -n "$TAIL" ]] && echo "$TAIL" || echo "$(read_ini "$TARGET" TAIL "$(read_ini default TAIL)")")
	DEBUG=$([[ -n "$DEBUG" ]] && echo "$DEBUG" || echo "$(read_ini "$TARGET" DEBUG "$(read_ini default DEBUG)")")

elif [ -n "$CONFIG_FILE" ] && [ ! -f "$CONFIG_FILE" ]; then
	echo "File '$CONFIG_FILE' does not exist."
	exit 1
fi

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
