If this is not already a feature of the RMM project impliment it.  


You are refactoring the RMM (Remote Monitoring and Management) application. The goal is to enhance the "Add a Site" interface by adding support for importing contact information from external files exported by email programs or contact managers.

Specifically, implement the following feature:

In the "Add a Site" form/screen, provide a clear and user-friendly option to import a contact from a file. The supported file formats are:
- .csv (commonly exported from Outlook, Google Contacts, etc.)
- .vcf (vCard, single or multiple contacts)
- .contact (Windows Contacts format)
- .wab (Windows Address Book)
- .ldif (LDAP Data Interchange Format)

The import process should:
1. Allow the user to select one of these file types.
2. Parse the file correctly according to its format.
3. If the file contains only one contact, automatically map and pre-fill the relevant fields in the new site form.
4. If the file contains multiple contacts (common in .csv or multi-entry .vcf files), present the user with a simple, intuitive selection interface (e.g., a searchable list or dropdown with key details like name, company, and email) so they can choose the desired contact with the fewest possible clicks.
5. Once a contact is selected (or automatically chosen if only one exists), extract and populate the most relevant information into the "Add a Site" form fields. Prioritize mapping the following data where available:
   - Company name → Site Name or Company field
   - First Name, Last Name → Primary Contact Name
   - Job Title
   - Department
   - Business Phone(s), Mobile Phone → Phone fields
   - Business Fax
   - E-mail Address (primary), then E-mail 2/3 → Email field
   - Business Street, City, State, Postal Code, Country/Region → Address fields
   - Any additional useful fields (e.g., Notes, Website) should be mapped if corresponding fields exist in the site form.

For reference, a typical Outlook CSV export includes these headers (use them to guide mapping logic):
First Name, Middle Name, Last Name, Title, Suffix, Nickname, Given Yomi, Surname Yomi, E-mail Address, E-mail 2 Address, E-mail 3 Address, Home Phone, Home Phone 2, Business Phone, Business Phone 2, Mobile Phone, Car Phone, Other Phone, Primary Phone, Pager, Business Fax, Home Fax, Other Fax, Company, Main Phone, Callback, Radio Phone, Telex, TTY/TDD Phone, IMAddress, Job Title, Department, Company, Office Location, Manager's Name, Assistant's Name, Assistant's Phone, Company Yomi, Business Street, Business City, Business State, Business Postal Code, Business Country/Region, Home Street, Home City, Home State, Home Postal Code, Home Country/Region, Other Street, Other City, Other State, Other Postal Code, Other Country/Region, Personal Web Page, Spouse, Schools, Hobby, Location, Web Page, Birthday, Anniversary, Notes

Ensure the import feature is robust:
- Handle missing columns gracefully (do not crash if a header is absent).
- Provide clear feedback or error messages if the file cannot be parsed or is unsupported.
- Prioritize a smooth user experience with minimal steps and intuitive UI elements.

Implement this in a clean, maintainable way, following existing code style and patterns in the RMM codebase.
