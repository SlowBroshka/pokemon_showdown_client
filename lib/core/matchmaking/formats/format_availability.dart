/// These reasons concern format metadata only, never authentication or queues.
enum FormatAvailability {
  experimental,
  staleCatalog,
  malformedCatalog,
  legacyCatalog,
  notAdvertised,
  unsupportedFormat,
  unsupportedFlags,
  searchDisabled,
  teamRequired,
  experimentalDisabled,
}
