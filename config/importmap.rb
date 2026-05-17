# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/channels", under: "channels"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@xterm/addon-fit", to: "@xterm--addon-fit.js" # @0.11.0
pin "@xterm/addon-search", to: "@xterm--addon-search.js" # @0.16.0
pin "@xterm/addon-web-links", to: "@xterm--addon-web-links.js" # @0.12.0
pin "xterm" # @5.3.0
# chart.js + @kurkle/color are pinned to ga.jspm.io with explicit SRI hashes.
# Rotation cost: each version bump requires recomputing the sha384 of the
# new URL (see Phase 5 H5 commit for the bash snippet). The browser refuses
# to execute the module if the hash mismatches the served bytes — protects
# against a compromised CDN serving tampered JS.
#
#   URL="https://ga.jspm.io/npm:chart.js@4.4.4/auto/auto.js"
#   curl -sf "$URL" | openssl dgst -sha384 -binary | openssl base64 -A
#
pin "chart.js",
  to: "https://ga.jspm.io/npm:chart.js@4.4.4/auto/auto.js",
  integrity: "sha384-ZXI0ulOS8KAQMtVZgZZg2sfQr1Lt1A0n+FN9D32IJy/x3ULiI/Nugf/Ba0XUfGdJ"

pin "@kurkle/color",
  to: "https://ga.jspm.io/npm:@kurkle/color@0.3.2/dist/color.esm.js",
  integrity: "sha384-g4B9JuefAPyFwI3R+BMY5UJRbvurFGA4GsMzVPtOsNTL2uy3HIkYilc3OvUnNj/D"

# sortablejs powers the swarm kanban drag-and-drop. Pinned to esm.sh per the
# Phase 6 plan; if you bump versions, ensure the new URL is still ESM.
pin "sortablejs", to: "https://esm.sh/sortablejs@1.15.0"
