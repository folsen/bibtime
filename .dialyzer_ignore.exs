[
  # Known false positive: Gettext.Backend generates code that triggers
  # opaque type warnings with Expo.PluralForms
  {"lib/bibtime_web/gettext.ex", :call_without_opaque}
]
