#!/bin/bash -eu

# Utility function for a simple message.
msg() {
  echo "${SCRIPT_NAME:-initializer}:" "$@"
}

# Utility function for an error message.
err() {
  echo "${SCRIPT_NAME:-initializer}:" "$@" 1>&2
}

# Utility function for a fatal error.
die() {
  err "$@"
  exit 1
}

# Check for required variables.
[ -n "${SCRIPT_NAME:-}" ] || die "error: SCRIPT_NAME: environment variable missing or empty"
[ -n "${STATE_CONFIGMAP:-}" ] || die "error: STATE_CONFIGMAP: environment variable missing or empty"

# Utility function that acts as a sentry before running initialization steps.
state_can_run() {
  local step="$1" state
  state="$(cat "/app/prior-state/step-$step" 2>/dev/null || echo)"
  if [ "$state" == "no" ] || [ "$state" == "" ]; then
    msg "$step: - has not run, will run next"
  elif [ "$state" == "yes" ]; then
    msg "$step: - has already run previously"
    return 1
  else
    die "$step: - state is '$state' - refusing to continue!"
  fi
}

# Utility function to update state via our configmap
state_update() {
  local step="$1" state="$2"
  kubectl patch "configmap/${STATE_CONFIGMAP}" --type merge -p '{"data":{"step-'"$step"'" : "'"$state"'"}}'
  msg "$step: - recorded successful run"
}

# Allow the next script to use our utility functions.
export -f msg err die state_can_run state_update

# Log that we are going to start installing tools.
msg "000: Install tools, initialize state, wait for health."
msg "000: - installing tools"

# Install JQ
yum install -q -y jq &&

# Install kubectl
curl -SsLO "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION:-1.18.8}/bin/linux/amd64/kubectl" &&
mv kubectl /usr/bin/kubectl &&
chmod +x /usr/bin/kubectl

# Ensure state configmap exists
if ! kubectl get configmap "${STATE_CONFIGMAP}" >/dev/null 2>&1; then
  msg "000: - initializing state configmap"
  mkdir -p /app/temp/steps
  for step in $STATE_STEPS; do echo -n no >"/app/temp/steps/step-$step" ; done
  kubectl create configmap "${STATE_CONFIGMAP}" --from-file=/app/temp/steps
  rm -rf /app/temp/steps
else
  msg "000: - state configmap already exists"
fi

# Wait for the deployment to be availabl, up to 2 minutes.
if [ "$DEPENDENT_DEPLOYMENT" != "none" ] ; then
  msg "000: - waiting (up to 2 minutes) for $DEPENDENT_DEPLOYMENT to become available"
  kubectl wait --for=condition=available --timeout=120s deployment "$DEPENDENT_DEPLOYMENT"
fi

# Wait another 2 minutes seconds for the app start up.
if [ -n "$EXTRA_SLEEP" ] && [ "$EXTRA_SLEEP" != "0" ]; then
  msg "000: - waiting for an extra $EXTRA_SLEEP seconds"
  sleep "$EXTRA_SLEEP"
fi
