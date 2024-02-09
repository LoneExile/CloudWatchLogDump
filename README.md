# AWS CloudWatch Logs Dump

This repository contains a script for fetching logs from AWS CloudWatch.

## Features

- **List Log Groups**: Easily list all available log groups in your AWS account.
- **Fetch Log Streams**: Retrieve log streams from a specified log group with optional filtering.
- **Fetch Logs**: Get logs from a specified log stream within a log group.
- **Configurable**: Use command-line options or a configuration file to specify parameters such as the AWS profile, log group, log stream, and filter patterns.
- **Flexible Logging**: Fetch logs based on a custom filter pattern and control the number of iterations for log fetching.
- **Interactive Mode**: Use the script interactively to select profiles, log groups, and log streams.

## Prerequisites

Before you can use this script, you need to have the following installed:

- [AWS CLI V2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) - The script interacts with AWS CloudWatch Logs through the AWS Command Line Interface.
- [jq](https://github.com/jqlang/jq) - A lightweight and flexible command-line JSON processor, used for parsing the output from AWS CLI commands.

Additionally, you should configure your AWS CLI with the necessary credentials and default region using `aws configure`.

## Getting Started

1. **Clone the Repository**

```bash
git clone https://github.com/LoneExile/CloudWatchLogDump
cd CloudWatchLogDump
```

2. **Make the Script Executable**

```bash
chmod +x CloudWatchLogDump.sh
```

3. **Run the Script**

The script offers multiple functionalities. Here are some common usages:

- Interactive mode:

```bash
./CloudWatchLogDump.sh
```

- List all log groups:

```bash
./CloudWatchLogDump.sh ls -p your-profile-name
```

- Fetch log streams from a log group:

```bash
./CloudWatchLogDump.sh -l your-log-group-name -p your-profile-name
```

- Fetch logs from a log stream:

```bash
./CloudWatchLogDump.sh -l your-log-group-name -s your-log-stream-name -p your-profile-name
```

For detailed information on all options and usage, run:

```bash
./CloudWatchLogDump.sh -h
```

Configuration File
You can also use a configuration file to specify the parameters for fetching logs. The configuration file format is key-value pairs, and you can specify the target configuration by appending `=target` when using the `-F` option.

Example `config.ini` content:

```ini
[default]
LOG_GROUP_NAME=my-log-group
PROFILE=my-aws-profile
FILTER_PATTERN="part of the log stream name"
MAX_ITERATIONS=2
```

To use the configuration file:

```bash
./CloudWatchLogDump.sh -F config.ini=default
```

## Contributing

Contributions to improve the script or add new features are welcome.

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
