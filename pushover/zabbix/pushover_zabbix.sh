#!/bin/bash

self=$(basename $0)
self_cfg=${self%.*}.cfg
if [ -s ${self_cfg} ]; then
  cfg=${self_cfg}
else
  if [ -s /etc/${self_cfg} ]; then
    cfg=/etc/${self_cfg}
  else
    echo "Configuration file not found. Please check ${self_cfg} exist in current directory or /etc/${self_cfg}!"
    exit 1
  fi
fi

#Set a default value for variables
source ${cfg}
#PTOKEN=""
#PUSER=""
#PDEVICE=""
#PTITLE=""
#PMESSAGE=""
#PPRIORITY=""	# -2
#PSOUND=""
#PRETRY=""	# 2
#PEXPIRE=""	# 60
#PURL=""
#PURL_TITLE=""
#PTIMESTAMP=""
#PCALLBACK=""
#PHTML=""

# Other Variables
ZASPATH=/usr/lib/zabbix/alertscripts
CURL="$(which curl)"
CURL_OPTS=""
PUSHOVER_URL="https://api.pushover.net/1/messages.json"

# Get CMD Parameters
CUSER=$(echo $1 | cut -f1 -d'@')
CDEVICE=$(echo $1 | cut -f2 -d'@')
CTOKEN=$(echo $1 | cut -f3 -d'@')
CTITLE=$2 
CMESSAGE=$3


# Functions

opt_field() {
    field=$1
    shift
    value="${*}"
    if [ ! -z "${value}" ]; then
        echo "-F \"${field}=${value}\""
    fi
}

validate_token() {
	field="${1}"
	value="${2}"
	ret=1
	if [ -z "${value}" ]; then
		echo "${field} is unset or empty: Did you specify ${field} on the command line?" >&2
	elif ! echo "${value}" | egrep -q '[A-Za-z0-9]{30}'; then
		echo "Value of ${field}, \"${value}\", does not match expected format. Should be 30 characters of A-Z, a-z and 0-9." >&2;
	else
		ret=0
	fi
	return ${ret}
}

severity_to_priority() {
local	priority=-2
local	severity="${1}"

	case $severity in
		Information)	priority=-2 ;;
		Warning)	priority=-1 ;;
		Average)	priority=0  ;;
		High)		priority=1  ;;
		Disaster)	priority=2; PRETRY="2"; PEXPIRE="60" ;;
	esac
	echo $priority
}

set_field() {
local	field="${1}"
local	value="${2}"
	case $field in
		TOKEN)          PTOKEN=$value;
				validate_token "TOKEN" "${PTOKEN}" || exit $? ;;
		USER)		PUSER=$value
				validate_token "USER" "${USER}" || exit $? ;;
		DEVICE)		PDEVICE=$value ;;
		TITLE)		PTITLE=$value ;;
		PRIORITY)	PPRIORITY=$(severity_to_priority "$value");
				if [ $PPRIORITY -ge 2 ]; then PRETRY=600; PEXPIRE=3600; fi ;;
		SOUND)		PSOUND=$value ;;
		RETRY)		PRETRY=$value ;;
		EXPIRE)		PEXPIRE=$value ;;
		URL)		PURL=$value ;;
		URL_TITLE)	PURL_TITLE=$value ;;
		TIMESTAMP)	PTIMESTAMP=$value ;;
		CALLBACK)	PCALLBACK=$value ;;
		HTML)		PHTML=$value ;;
	esac
}

send_message() {
    local device="${1:-}"

    curl_cmd="\"${CURL}\" -s -S \
        ${CURL_OPTS} \
        -F \"token=${PTOKEN}\" \
        -F \"user=${PUSER}\" \
        -F \"message=${PMESSAGE}\" \
        $(opt_field device "${PDEVICE}") \
        $(opt_field callback "${PCALLBACK}") \
        $(opt_field timestamp "${PTIMESTAMP}") \
        $(opt_field priority "${PPRIORITY}") \
        $(opt_field retry "${PRETRY}") \
        $(opt_field expire "${PEXPIRE}") \
        $(opt_field title "${PTITLE}") \
        $(opt_field sound "${PSOUND}") \
        $(opt_field url "${PURL}") \
        $(opt_field url_title "${PURL_TITLE}") \
	$(opt_field html "${PHTML}") \
        \"${PUSHOVER_URL}\""

    # execute and return exit code from curl command
    response="$(eval "${curl_cmd}")"
    # TODO: Parse response for value of status to give better error to user
    r="${?}"
    if [ "${r}" -ne 0 ]; then
        echo "${0}: Failed to send message" >&2
    fi

    return "${r}"
}


if [ -z "$PUSER" ]; then PUSER=$CUSER; fi
if [ -z "$PDEVICE" ] && [ -n "$CDEVICE" ]; then PDEVICE=$CDEVICE; fi
if [ -z "$PTOKEN" ] && [ -n "$CTOKEN" ]; then PTOKEN=$CTOKEN; fi
if [ -z "$PTITLE" ]; then PTITLE=$CTITLE; fi
if [ -z "$PMESSAGE" ]; then PMESSAGE=$CMESSAGE; fi

# Cut pushover rows from Message
POPTS=$(echo "${PMESSAGE}" | grep -i %PUSHOVER%)
PMESSAGE=$(echo "${PMESSAGE}" | grep -iv %PUSHOVER%)

OLDIFS=$IFS
IFS=$'\n'
for PL in ${POPTS}
do
	OPT=$(echo $PL | cut -f3 -d'%')
	VAL=$(echo $PL | cut -f4 -d'%')
	set_field "$OPT" "$VAL"
done
IFS=$OLDIFS

send_message
