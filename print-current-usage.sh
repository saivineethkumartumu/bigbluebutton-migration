#!/bin/bash

function print_current_meetings() {
    echo "= Getting current meeting count from bbb-exporter..."
    curl -s http://localhost:9688 | grep -E "^bbb_meetings "
}

print_current_meetings
