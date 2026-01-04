If this is not already a feature of the RMM project impliment it.  

You are an expert PowerShell developer and UI/UX refactoring specialist working on an open-source Remote Monitoring and Management (RMM) platform built in PowerShell, targeted at IT technicians and small-to-medium Managed Service Providers (MSPs) managing SMB clients. The full codebase is open in Visual Studio Code and being actively analyzed and refactored with Augment AI.

Your primary task is to fully refactor and restore the missing individual action controls on the "Sites and Devices" page while ensuring a cohesive, intuitive, and professional user experience. Additionally, implement proper defaulting behavior so that any new device automatically inherits the parent site's identity and settings.

Specific requirements:

1. **Site List Header Controls (global actions for Sites, placed in the header above or adjacent to the main Site list):**
   - "+ Add Site" button: Opens the new Site creation dialog/form.
   - "Import Site" button: Triggers the Site import workflow (e.g., from CSV, JSON, or other supported formats).
   - "Export Site" button: Exports the selected Site(s) or all Sites if none selected.

   Group these buttons logically in a toolbar or button row. Use consistent styling, icons (if supported by the UI framework), tooltips, and ensure they are only enabled when appropriate (e.g., Export disabled if no Sites exist).

2. **Per-Site Device Table Header Controls (actions scoped to an individual Site, placed in the header of each Site's collapsible/expandable section):**
   For every Site entry that contains its own Device table:
   - Site-level actions:
     - "Edit" button: Opens the edit dialog for the current Site's properties (name, notes, credentials, etc.).
     - "Export" button: Exports data for this specific Site only (including all associated Devices).
     - "Delete" button: Permanently deletes the Site and all its Devices (must include a clear confirmation prompt with warning about data loss).
   - Device-level actions:
     - "+ Add Device" button: Opens the new Device creation dialog, pre-populated with defaults from the parent Site (see below).
     - "Import Device" button: Triggers bulk import of Devices directly into this specific Site.
     - "Export Device" button: Exports all or selected Devices belonging to this Site.

   Visually group Site-level and Device-level buttons separately within the same header (e.g., Site actions on the left, Device actions on the right) to avoid confusion. Ensure controls are clearly scoped to the current Site and are disabled if the Site section is collapsed or in an invalid state.

3. **New Device Defaulting Behavior (critical data integrity requirement):**
   - Whenever a Device is created via "+ Add Device" under a specific Site (either through the UI button or programmatically), the new Device record MUST automatically default its Site association to the parent Site.
   - Pre-populate any Site-specific fields in the "Add Device" dialog with values inherited from the parent Site, including but not limited to:
     - Site ID / Site Name
     - Customer/Client name
     - Default credentials (if stored per-Site)
     - Billing/contact information
     - Any Site-level tags, groups, or policies
   - This defaulting must occur both in the UI form (for immediate user visibility) and in the underlying data model (when saving the new Device object).
   - If a global "Add Device" action exists outside of a Site context, it should either:
     - Prompt the user to select a Site first, or
     - Default to a configured "default Site" if one exists, or
     - Disable the action with a tooltip explaining a Site must be selected.
   - Ensure that imported Devices (via "Import Device") also respect Site context: if imported from within a Site's section, assign them to that Site by default unless explicitly overridden in the import data.

General refactoring and implementation guidelines:
- Adhere strictly to the existing codebase style, naming conventions, module structure, and UI framework (Windows Forms, WPF, Out-GridView, or custom).
- Implement robust error handling, input validation, and user feedback (progress indicators, toast notifications, success/error messages) for all actions.
- Add or update comments explaining the purpose and behavior of new/modified controls and defaulting logic.
- Ensure accessibility: proper labels, tooltips, keyboard shortcuts, and ARIA-equivalent attributes where applicable.
- Maintain responsiveness and existing theming.
- Wire new controls to existing handler functions where possible; create new modular, reusable functions only when necessary.
- Do not introduce breaking changes to existing data structures unless absolutely required—prefer non-destructive enhancements.
- Test edge cases: no Sites exist, single Site, many Sites, adding Devices with/without pre-existing defaults.

Focus exclusively on the "Sites and Devices" page and any shared modules directly required for these features. Prioritize usability for time-constrained MSP technicians: actions should be discoverable, predictable, and minimize required clicks while preventing accidental data loss or misassignment.