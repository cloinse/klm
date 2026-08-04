import Foundation

let validApplication = URL(
  fileURLWithPath: "/Applications/Kontakt Library Manager.app"
)
let nestedApplication = URL(
  fileURLWithPath: "/Applications/Audio/Kontakt Library Manager.app"
)
let downloadsApplication = URL(
  fileURLWithPath: "/Users/example/Downloads/Kontakt Library Manager.app"
)
let translocatedApplication = URL(
  fileURLWithPath:
    "/private/var/folders/example/AppTranslocation/example/d/Kontakt Library Manager.app"
)

precondition(InstallationLocationValidator.isAllowed(bundleURL: validApplication))
precondition(InstallationLocationValidator.isAllowed(bundleURL: nestedApplication))
precondition(!InstallationLocationValidator.isAllowed(bundleURL: downloadsApplication))
precondition(!InstallationLocationValidator.isAllowed(bundleURL: translocatedApplication))

print("Installation location validation passed.")
