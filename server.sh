#!/usr/bin/env bash

# port constant
PORT="${1:-1234}"
# constants for assignment reference
UNIT_URL="https://www.sydney.edu.au/units/INFO1112/2026-S2C-ND-CC"
# constants for population reference
POPULATION_URL="https://dbr.abs.gov.au/processedData/csv/STE_1.csv"
POPULATION_ROW_CODE="ERP_P_20"
# constants for POI reference
# constants for POI reference (NSW Spatial Services, as in Lab 10)
POI_URL="https://maps.six.nsw.gov.au/arcgis/rest/services/public/NSW_POI/MapServer/0/query"
POI_RADIUS=1000
POI_LIMIT=15

WORKDIR="/tmp/a2server"
LOCKDIR="$WORKDIR/locks"

SELF="$(readlink -f "$0")"
PLOT_SCRIPT="$(dirname "$SELF")/plot.py"

# installs required tools for the running of the server, even if they are already downloaded as confirmation
install_tools(){
  apk add --no-cache curl html2text python3 py3-matplotlib nmap-ncat iproute2 jq >/dev/null
}

# handles ONE client connection (ncat runs a copy of this for each client)
handle_connection(){
  # ncat sets these for each client
  client_IP="$NCAT_REMOTE_ADDR"
  # prints the successful connection with the server
  echo "Connection received on $client_IP $NCAT_REMOTE_PORT" >&2

  # directory of IP requests, where each IP is limited to 1 request
  mkdir -p "$LOCKDIR"
  if ! mkdir "$LOCKDIR/$client_IP" 2>/dev/null; then
    echo "Rejected $client_IP: a request from this IP is being served" >&2
    echo "ERROR: server is busy with your previous request - rejected"
    exit 1
  fi
  # free the lock however we exit
  trap 'rmdir "$LOCKDIR/$client_IP" 2>/dev/null' EXIT
  sleep 1

  # read one request line, limited to 10s
  local request cmd arg
  # stops if nothing arrives
  if ! IFS= read -r -t 10 request && [ -z "$request" ]; then
    # printed to the server
    echo "ERROR: no request received" >&2
    # printed to the client
    echo "ERROR: no request received"
    exit 1
  fi
  # separates each line into 3 things, plus trimmings
  request=$(echo "$request" | tr -d '\r' | sed 's/^ *//; s/ *$//')
  cmd=$(echo "$request" | awk '{print tolower($1)}')
  arg=$(echo "$request" | cut -s -d' ' -f2-)

  # dispatch to the right handler
  case "$cmd" in
    assignment) handle_assignment "$arg" ;;
    population) handle_population ;;
    "")         echo "ERROR: empty request" >&2; echo "ERROR: empty request" ;;
    *)          handle_poi "$request" ;;
  esac
}

# a function for when an assignment was called
handle_assignment(){
  # variables storing the desired url and file
  local wanted="$1"
  local html="$WORKDIR/unit.html"
  local text="$WORKDIR/unit.txt"

  # download desired url
  curl -sf -o "$html" "$UNIT_URL" || {
    echo "could not download $UNIT_URL" >&2
    echo "could not download $UNIT_URL"
    exit 1
  }

  # convert the html file into text, setting a high width limit to keep everything in one line
  html2text -width 400 "$html" > "$text"

  # if no assignment number is given, then we default to the latest number
  if [ -z "$wanted" ]; then
    wanted=$(grep -o "Assignment [0-9][0-9]*" "$text" | grep -o "[0-9][0-9]*" | sort -n | tail -n 1)
  fi

  # extract the specific lines required for assignment (the match + the 2 lines after it)
  rows=$(grep -A 2 "Assignment $wanted" "$text")

  if [ -z "$rows" ]; then
    echo "Assignment not found" >&2
    echo "Assignment not found"
    exit 1
  fi

  # shows the assignment in the server side
  echo "$rows" >&2

  # extract fields from wanted line
  title="Assignment $wanted"

  # grab points, due_date, topic
  points=$(echo "$rows" | grep -o "[0-9][0-9]*%" | head -n 1 | tr -d '%')
  due_date=$(echo "$rows" | grep -o "Due date: .* at [0-9:]*" | head -n 1 | sed 's/Due date: //; s/ at / /')
  topic=$(echo "$rows" | grep -o "task - [A-Za-z]*" | head -n 1 | sed 's/task - //')

  # validity check, regarding whether or not data is there
  # if empty, print to server and to client about error
  if [ -z "$points" ]; then
    echo "the data point for 'points' is empty or cannot be read" >&2
    echo "the data point for 'points' is empty or cannot be read"
    exit 1
  fi
  if [ -z "$due_date" ]; then
    echo "the data point for 'due_date' is empty or cannot be read" >&2
    echo "the data point for 'due_date' is empty or cannot be read"
    exit 1
  fi
  if [ -z "$topic" ]; then
    echo "the data point for 'topic' is empty or cannot be read" >&2
    echo "the data point for 'topic' is empty or cannot be read"
    exit 1
  fi

  # a variable where the json file is saved
  json="$WORKDIR/assignment.json"

  # writing results into a json file as required
  {
    echo "{"
    echo "    \"title\" : \"$title\","
    echo "    \"topic\" : \"$topic\","
    echo "    \"due_date\" : \"$due_date\","
    echo "    \"points\" : $points"
    echo "}"
  } > "$json"

  cat "$json"
}
handle_population(){
  # variables storing the desired url and files
  csv="$WORKDIR/STE_1.csv"
  clean_csv="$WORKDIR/clean.csv"
  data="$WORKDIR/population_data.csv"
  png="$WORKDIR/population.png"

  # download desired url
  curl -sf -o "$csv" "$POPULATION_URL" || {
    echo "could not download $POPULATION_URL" >&2
    echo "could not download $POPULATION_URL"
    exit 1
  }

  # removes \r character from csv file
  tr -d '\r' < "$csv" > "$clean_csv"

  # pairs years (header row) with population (ERP row)
  awk -F',' -v code="$POPULATION_ROW_CODE" '
    NR == 1 { for (i=4; i<=NF; i++) y[i]=$i }
    $1 == code {
      for (i=4; i<=NF; i++)
      if ($i != "") print y[i] "," $i
    }
  ' "$clean_csv" > "$data"

  # stops if no population data was found
  if [ ! -s "$data" ]; then
    echo "no population data was found in the csv" >&2
    echo "no population data was found in the csv"
    exit 1
  fi

  # the last line is the latest year
  latest_year=$(tail -n 1 "$data" | cut -d',' -f1)
  latest_pop=$(tail -n 1 "$data" | cut -d',' -f2)

  # displays what the latest year is in the server side
  echo "NSW population ($latest_year): $latest_pop" >&2

  # removes old, potentially corrupted png file
  rm -f "$png"

  # stop if plot.py isn't next to server.sh
  if [ ! -f "$PLOT_SCRIPT" ]; then
    echo "could not find $PLOT_SCRIPT (copy plot.py into the container with server.sh)" >&2
    echo "could not create population.png (plot.py missing)"
    exit 1
  fi

  # draws the line plot (x = year, y = population) with plot.py
  # (the data was read from the csv with Bash/awk above; Python only draws it)
  python3 "$PLOT_SCRIPT" "$data" "$png" 2>/dev/null

  # stop if the plot wasn't created
  if [ ! -s "$png" ]; then
    echo "could not create population.png" >&2
    echo "could not create population.png"
    exit 1
  fi

  # send only the image to the client
  cat "$png"
}
handle_poi(){
  request="$1"
  found="$WORKDIR/found.json"
  places="$WORKDIR/places.json"
  json="$WORKDIR/neighbours.json"

  # clear results from a previous request
  rm -f "$found" "$places"

  # if the request is already "lat,lon", use it directly
  if echo "$request" | grep -qE '^-?[0-9.]+,-?[0-9.]+$'; then
    latitude=$(echo "$request" | cut -d ',' -f1)
    longitude=$(echo "$request" | cut -d ',' -f2)
  else
    # POI names are stored in capitals; a ' in the name must be doubled for the where clause
    name=$(echo "$request" | tr 'a-z' 'A-Z' | sed "s/'/''/g")

    # ask the NSW POI service for the place with this exact name (like the lab's nswPOI.sh)
    curl -sf -G --max-time 20 \
      --data-urlencode "where=poiname='$name'" \
      --data-urlencode "outFields=poiname,poitype" \
      --data-urlencode "returnGeometry=true" \
      --data-urlencode "outSR=4326" \
      --data-urlencode "f=json" \
      -o "$found" "$POI_URL" || {
      echo "could not download $POI_URL" >&2
      echo "could not download $POI_URL"
      exit 1
    }

    # geometry.x is the longitude, geometry.y is the latitude (outSR=4326 = normal lat/lon)
    longitude=$(jq -r '.features[0].geometry.x // empty' "$found")
    latitude=$(jq -r '.features[0].geometry.y // empty' "$found")
  fi

  # if there is nothing in longitude and latitude, then an error is echo-ed
  if [ -z "$latitude" ] || [ -z "$longitude" ]; then
    echo "the POI '$request' cannot be found" >&2
    echo "the POI '$request' cannot be found"
    exit 1
  fi

  echo "POI '$request' is at $latitude, $longitude" >&2

  # ask the same service for every POI within POI_RADIUS metres of that point
  curl -sf -G --max-time 20 \
    --data-urlencode "geometry=$longitude,$latitude" \
    --data-urlencode "geometryType=esriGeometryPoint" \
    --data-urlencode "inSR=4326" \
    --data-urlencode "distance=$POI_RADIUS" \
    --data-urlencode "units=esriSRUnit_Meter" \
    --data-urlencode "outFields=poiname,poitype" \
    --data-urlencode "outSR=4326" \
    --data-urlencode "f=json" \
    -o "$places" "$POI_URL" || {
    echo "could not download $POI_URL" >&2
    echo "could not download $POI_URL"
    exit 1
  }

  # the service reports query problems as {"error": ...} instead of a failed download
  if jq -e '.error' "$places" >/dev/null 2>&1; then
    echo "the POI service rejected the query: $(jq -c '.error' "$places")" >&2
    echo "the POI service rejected the query"
    exit 1
  fi

  # build neighbours.json with jq: every feature except the POI itself, up to POI_LIMIT
  jq --arg query "$request" --arg self "$(echo "$request" | tr 'a-z' 'A-Z')" \
    --argjson lat "$latitude" --argjson lon "$longitude" --argjson limit "$POI_LIMIT" '
    {
      query: $query,
      lat: $lat,
      lon: $lon,
      neighbours: [ .features[]
                    | select(.attributes.poiname != null and .attributes.poiname != $self)
                    | { name: .attributes.poiname,
                        type: .attributes.poitype,
                        lat:  .geometry.y,
                        lon:  .geometry.x } ]
                  | sort_by((.lat - $lat) * (.lat - $lat) + (.lon - $lon) * (.lon - $lon))
                  | .[:$limit]
    }' "$places" > "$json"

  # sending the json file to the client
  cat "$json"

}

# finds ip address of system
find_ip(){
  # ifconfig to find data
  # grep -E to obtain string
  # sed to remove the string, leaving just the numbers
  # grep -v to remove the option that starts with 127.X.X.X
  ifconfig | grep -E -o 'inet addr:[0-9.]+' | sed -E 's/inet addr://' | grep -v '^127\.' | head -n1
}
# finds the port that the ncat listener is bounded to
find_port(){
  # ss -ltnp to find the active listening port that the ncat is linked to
  # greps the correct process_id
  # filters for the 0.0.0.0 address
  # awk to take the 4th column
  # sed to remove 0.0.0.0:
  ss -ltnp | grep "pid=$ncat_pid," | grep '0\.0\.0\.0' | awk '{print $4}' | sed -E 's/0\.0\.0\.0://' |head -n1
}

main(){
  # installs tools first
  install_tools
  mkdir -p "$WORKDIR" && rm -rf "$LOCKDIR"

  # starts the listener in the background and saves PID so find_port and trap can target the ncat 
  ncat -lk "$PORT" --sh-exec "bash '$SELF' --handle" &
  ncat_pid=$!
  trap 'kill "$ncat_pid" 2>/dev/null; exit 0' INT TERM

  # pauses for a second
  sleep 1

  # stores port after output from find_port
  port=$(find_port)
  [ -n "$port" ] || { echo "ERROR: listener did not start (port $PORT in use)"; exit 1; }
  # store ip after output from find_ip
  ip=$(find_ip)
  [ -n "$ip" ] || echo "WARNING: could not find a non-loopback IP address"
  
  # print as required
  echo "The server is running at $ip, port=$port"
  echo "Listening on 0.0.0.0 $port"
  
  # pauses here until listener exits (ie until trap is executed)
  wait "$ncat_pid"
}
if [ "$1" = "--handle" ]; then 
  handle_connection; 
else
  main;
fi
