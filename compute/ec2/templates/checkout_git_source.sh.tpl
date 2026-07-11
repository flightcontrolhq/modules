SOURCE_REPO="{{ sourceRepo }}"
SOURCE_BRANCH="{{ sourceBranch }}"
SOURCE_REF="{{ sourceRef }}"
SOURCE_BASE_PATH="{{ sourceBasePath }}"
GIT_TOKEN_PARAMETER_NAME="{{ gitTokenParameterName }}"
SOURCE_ROOT="/srv/ravion/${name}"
SOURCE_DIRECTORY="$SOURCE_ROOT/source"
SOURCE_STAGING_DIRECTORY="$SOURCE_ROOT/.source-$DEPLOY_ID"
SOURCE_WORKING_DIRECTORY_FILE="${source_working_directory_path}"

if [ -z "$SOURCE_REPO" ]; then
  rm -f "$SOURCE_WORKING_DIRECTORY_FILE"
else
  if [ -z "$GIT_TOKEN_PARAMETER_NAME" ]; then
    echo "Git source requires a temporary credential parameter" >&2
    exit 1
  fi

  GIT_CREDENTIAL=$(aws ssm get-parameter \
    --name "$GIT_TOKEN_PARAMETER_NAME" \
    --with-decryption \
    --region "${region}" \
    --query 'Parameter.Value' \
    --output text)
  if [ -z "$GIT_CREDENTIAL" ] || [ "$GIT_CREDENTIAL" = "None" ]; then
    echo "Git credential parameter returned no value" >&2
    exit 1
  fi

  case "$GIT_CREDENTIAL" in
    *:*)
      RVN_GIT_USERNAME=$${GIT_CREDENTIAL%%:*}
      RVN_GIT_PASSWORD=$${GIT_CREDENTIAL#*:}
      ;;
    *)
      RVN_GIT_USERNAME="x-access-token"
      RVN_GIT_PASSWORD="$GIT_CREDENTIAL"
      ;;
  esac
  unset GIT_CREDENTIAL
  export RVN_GIT_USERNAME RVN_GIT_PASSWORD GIT_TERMINAL_PROMPT=0

  GIT_ASKPASS_SCRIPT=$(mktemp /tmp/ravion-git-askpass.XXXXXX)
  cleanup_git_credentials() {
    rm -f "$GIT_ASKPASS_SCRIPT"
    rm -rf "$SOURCE_STAGING_DIRECTORY"
    unset RVN_GIT_USERNAME RVN_GIT_PASSWORD GIT_ASKPASS
  }
  trap cleanup_git_credentials EXIT
  cat > "$GIT_ASKPASS_SCRIPT" <<'GIT_ASKPASS'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "$RVN_GIT_USERNAME" ;;
  *) printf '%s\n' "$RVN_GIT_PASSWORD" ;;
esac
GIT_ASKPASS
  chmod 700 "$GIT_ASKPASS_SCRIPT"
  export GIT_ASKPASS="$GIT_ASKPASS_SCRIPT"

  case "$SOURCE_REPO" in
    git@*:*)
      SOURCE_REPO_HOST=$${SOURCE_REPO#git@}
      SOURCE_REPO_HOST=$${SOURCE_REPO_HOST%%:*}
      SOURCE_REPO_PATH=$${SOURCE_REPO#*:}
      SOURCE_REPO="https://$SOURCE_REPO_HOST/$SOURCE_REPO_PATH"
      ;;
  esac

  mkdir -p "$SOURCE_ROOT"
  rm -rf "$SOURCE_STAGING_DIRECTORY"
  git clone --no-checkout "$SOURCE_REPO" "$SOURCE_STAGING_DIRECTORY"

  if [ -z "$SOURCE_BRANCH" ]; then
    SOURCE_BRANCH=$(git -C "$SOURCE_STAGING_DIRECTORY" symbolic-ref --short refs/remotes/origin/HEAD)
    SOURCE_BRANCH=$${SOURCE_BRANCH#origin/}
  fi
  git -C "$SOURCE_STAGING_DIRECTORY" fetch origin "$SOURCE_BRANCH" --tags

  if [ -n "$SOURCE_REF" ]; then
    git -C "$SOURCE_STAGING_DIRECTORY" checkout --detach "$SOURCE_REF"
  else
    git -C "$SOURCE_STAGING_DIRECTORY" checkout -B "$SOURCE_BRANCH" "origin/$SOURCE_BRANCH"
  fi
  git -C "$SOURCE_STAGING_DIRECTORY" submodule sync --recursive
  git -C "$SOURCE_STAGING_DIRECTORY" submodule update --init --recursive

  if [ -z "$SOURCE_BASE_PATH" ]; then SOURCE_BASE_PATH="."; fi
  SOURCE_WORKING_DIRECTORY=$(realpath -m "$SOURCE_STAGING_DIRECTORY/$SOURCE_BASE_PATH")
  case "$SOURCE_WORKING_DIRECTORY" in
    "$SOURCE_STAGING_DIRECTORY"|"$SOURCE_STAGING_DIRECTORY"/*) ;;
    *)
      echo "Git source base path must stay inside the repository" >&2
      exit 1
      ;;
  esac
  if [ ! -d "$SOURCE_WORKING_DIRECTORY" ]; then
    echo "Git source base path does not exist or is not a directory: $SOURCE_BASE_PATH" >&2
    exit 1
  fi

  rm -rf "$SOURCE_DIRECTORY"
  mv "$SOURCE_STAGING_DIRECTORY" "$SOURCE_DIRECTORY"
  SOURCE_WORKING_DIRECTORY=$(realpath -m "$SOURCE_DIRECTORY/$SOURCE_BASE_PATH")
  printf '%s' "$SOURCE_WORKING_DIRECTORY" > "$SOURCE_WORKING_DIRECTORY_FILE"
  chmod 600 "$SOURCE_WORKING_DIRECTORY_FILE"

  cleanup_git_credentials
  trap - EXIT
  cd "$SOURCE_WORKING_DIRECTORY"
fi
