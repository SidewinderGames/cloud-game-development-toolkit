# Authentication for the Spacelift provider:
#
# When this stack runs INSIDE Spacelift as an administrative stack, Spacelift
# automatically injects SPACELIFT_API_KEY_ENDPOINT and a session token. No
# explicit provider config is needed.
#
# For local development (one-off applies before the admin stack is registered),
# set these environment variables from a personal API key:
#   SPACELIFT_API_KEY_ENDPOINT  e.g. https://sidewinder-games.app.spacelift.io
#   SPACELIFT_API_KEY_ID
#   SPACELIFT_API_KEY_SECRET
provider "spacelift" {}
