#!/bin/bash
set -e

if [ -z "$PLUGIN_MOUNT" ]; then
    echo "Specify folders to cache in the mount property! Plugin won't do anything!"
    exit 0
fi

if [[ $DRONE_COMMIT_MESSAGE == *"[CLEAR CACHE]"* && -n "$PLUGIN_RESTORE" && "$PLUGIN_RESTORE" == "true" ]]; then
    if [ -d "/cache/$DRONE_REPO_OWNER/$PLUGIN_REPO_NAME" ]; then
        echo "Found [CLEAR CACHE] in commit message, clearing cache..."
        rm -rf "/cache/$DRONE_REPO_OWNER/$PLUGIN_REPO_NAME"
        exit 0
    fi
fi

if [[ $DRONE_COMMIT_MESSAGE == *"[NO CACHE]"* ]]; then
    echo "Found [NO CACHE] in commit message, skipping cache restore and rebuild!"
    exit 0
fi

CACHE_PATH="$DRONE_REPO_OWNER/$PLUGIN_REPO_NAME"
if [[ -n "$PLUGIN_CACHE_KEY" ]]; then
    function join_by { local IFS="$1"; shift; echo "$*"; }
    IFS=','; read -ra CACHE_PATH_VARS <<< "$PLUGIN_CACHE_KEY"
    CACHE_PATH_VALUES=()
    for env_var in "${CACHE_PATH_VARS[@]}"; do
        env_var_value="${!env_var}"
        
        if [[ -z "$env_var_value" ]]; then
            echo "Warning! Environment variable '${env_var}' does not contain a value, it will be ignored!"
        else
            CACHE_PATH_VALUES+=("${env_var_value}")
        fi
    done
    CACHE_PATH=$(join_by / "${CACHE_PATH_VALUES[@]}")
fi

IFS=','; read -ra SOURCES <<< "$PLUGIN_MOUNT"
if [[ -n "$PLUGIN_REBUILD" && "$PLUGIN_REBUILD" == "true" ]]; then
    # Create cache
    for source in "${SOURCES[@]}"; do
        if [ -d "$source" ]; then
            echo "Rebuilding cache for folder $source..."
            mkdir -p "/cache/$CACHE_PATH/$source" && \
                rsync -aHA --delete "$source/" "/cache/$CACHE_PATH/$source"
        elif [ -f "$source" ]; then
            echo "Rebuilding cache for file $source..."
            source_dir=$(dirname $source)
            mkdir -p "/cache/$CACHE_PATH/$source_dir" && \
                rsync -aHA --delete "$source" "/cache/$CACHE_PATH/$source_dir/"
        else
            echo "$source does not exist, removing from cached folder..."
            rm -rf "/cache/$CACHE_PATH/$source"
        fi
    done
elif [[ -n "$PLUGIN_RESTORE" && "$PLUGIN_RESTORE" == "true" ]]; then
    # Remove files older than TTL
    if [[ -n "$PLUGIN_TTL" && "$PLUGIN_TTL" > "0" ]]; then
        if [[ $PLUGIN_TTL =~ ^[0-9]+$ ]]; then
            if [ -d "/cache/$CACHE_PATH" ]; then
              echo "Removing files and (empty) folders older than $PLUGIN_TTL days..."
              find "/cache/$CACHE_PATH" -type f -ctime +$PLUGIN_TTL -delete
              find "/cache/$CACHE_PATH" -type d -ctime +$PLUGIN_TTL -empty -delete
            fi
        else
            echo "Invalid value for ttl, please enter a positive integer. Plugin will ignore ttl."
        fi
    fi
    # Restore from cache
    for source in "${SOURCES[@]}"; do
        if [ -d "/cache/$CACHE_PATH/$source" ]; then
            echo "Restoring cache for folder $source..."
            mkdir -p "$source" && \
                rsync -aHA --delete "/cache/$CACHE_PATH/$source/" "$source"
        elif [ -f "/cache/$CACHE_PATH/$source" ]; then
            echo "Restoring cache for file $source..."
            source_dir=$(dirname $source)
            mkdir -p "$source_dir" && \
                rsync -aHA --delete "/cache/$CACHE_PATH/$source" "$source_dir/"
        else
            echo "No cache for $source"
        fi
    done
else
    echo "No restore or rebuild flag specified, plugin won't do anything!"
fi
