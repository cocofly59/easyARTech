#!/bin/sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

DIRECTORY_LOG="/tmp/eart"
DIRECTORY_PID="/tmp/eart/pid"

if [[ ! -d $DIRECTORY_LOG ]]
then
  mkdir $DIRECTORY_LOG
fi

if [[ ! -d $DIRECTORY_PID ]]
then
  mkdir $DIRECTORY_PID
fi

INFRA_CONTAINER_NAME="eart_easyartech-sql_1"

WITH_TAIL=true
WITH_BACK=true
WITH_FRONT=true

BACK_LOGS="${DIRECTORY_LOG}/back.log"
FRONT_LOGS="${DIRECTORY_LOG}/front.log"
INFRA_LOGS="${DIRECTORY_LOG}/infra.log"

FRONT_PID="${DIRECTORY_PID}/front.pid"
BACK_PID="${DIRECTORY_PID}/back.pid"
INFRA_PID="${DIRECTORY_PID}/infra.pid"

#-----------------------------------------------------------------------------------------------------------------------
# Functions
#-----------------------------------------------------------------------------------------------------------------------
function clean_log() {
  if [[ -f "$1" ]]
  then
    rm $1
  fi
}

function quit_back() {
  if is_back_started
  then
    if [[ -f $BACK_PID ]]
    then
      pid=$(cat $BACK_PID)
      echo "[INFO] Turning off back server ($pid)"
      kill "$pid"
      rm $BACK_PID
    else
      echo "[WARNING] Cannot stop the back server : cannot find the PID."
    fi
  fi
}

function quit_front() {
  if is_front_started
  then
    if [[ -f $FRONT_PID ]]
    then
      pid=$(cat $FRONT_PID)
      echo "[INFO] Turning off front server ($pid)"
      kill $pid
      rm $FRONT_PID
    else
      echo "[WARNING] Cannot stop the front server : cannot find the PID."
    fi
  fi
}

function quit_infra() {
  if is_infra_started
  then
    if [[ -f $INFRA_PID ]]
    then
      pid=$(cat $INFRA_PID)
      echo "[INFO] Killing infra log process ($pid)"
      kill $pid
      rm $INFRA_PID
    fi
    echo "[INFO] Turning off infra."
    mvn -f infra -Pstop &> /dev/null
  fi
}


function quit() {
  if $WITH_TAIL
  then
    echo "[INFO] Quitting..."
    quit_front
    quit_infra
    quit_back
    echo "[INFO] Done"
  fi
}

function is_infra_started() {
  answer=$(docker ps | grep $INFRA_CONTAINER_NAME)
  if [[ "$answer" == "" ]]
  then
    false
  else
    true
  fi
}

function is_front_started() {
  echo | nc localhost 4200
  if [[ $? -eq 0 ]]
  then
    true
  else
    false
  fi
}

function is_back_started() {
  echo | nc localhost 8080
  if [[ $? -eq 0 ]]
  then
    true
  else
    false
  fi
}

function help() {
    echo $1
    echo
    echo "Usage:"
    echo "------"
    echo "--without-back: do not start back"
    echo "--without-front: do not start front"
    echo "--without-tail: do not display logs, keep all process alive. Use --stop option to stop them."
    echo "--stop: stop all known process and quit."
    echo
    return 0
}


#-----------------------------------------------------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    key="$1"
    case ${key} in
        --without-back)
            WITH_BACK=false
            shift # past argument
            ;;
        --without-front)
            WITH_FRONT=false
            shift # past argument
            ;;
        --without-tail)
            WITH_TAIL=false
            shift # past argument
            ;;
        --stop)
          quit
          exit
          ;;
        -h|--help)
            shift
            help
            exit 0
            ;;
        *)    # unknown option
            help "Wrong parameter '$key'"
            exit 1
            ;;
    esac
done

trap quit EXIT

echo "[INFO] Compiling..."
mvn clean install -Plocal -DskipTests &> /dev/null
echo "[INFO] Compilation done."

# clean logs
clean_log $BACK_LOGS
clean_log $FRONT_LOGS
clean_log $INFRA_LOGS

# Go into the root folder
cd $SCRIPT_DIR || exit 1


# start infra
if ! is_infra_started
then
  echo "[INFO] Starting infra"
  mvn -f infra -Plocal,start &> /dev/null
fi

if $WITH_TAIL
then
  docker logs --follow $INFRA_CONTAINER_NAME > $INFRA_LOGS &
  echo $! > $INFRA_PID
fi

while ! is_infra_started
do
  sleep 1
done
echo "[INFO] infra started"

# start back
quit_back
if $WITH_BACK
then
  mvn -f back -Plocal,start &> $BACK_LOGS &
  echo $! > $BACK_PID
  echo "[INFO] Back server started."
else
  BACK_LOGS=""
fi

#start front
quit_front
if $WITH_FRONT
then
  mvn -f front -Plocal,start &> $FRONT_LOGS &
  echo $! > $FRONT_PID
  echo "[INFO] Front server started."
else
  FRONT_LOGS=""
fi

# display all logs
if $WITH_TAIL
then
  multitail "$BACK_LOGS" "$INFRA_LOGS" "$FRONT_LOGS"
fi


