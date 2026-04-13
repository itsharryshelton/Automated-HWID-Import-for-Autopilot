# Automated HWID Import for Autopilot (Version 2)

This tool automates the process of capturing a device's Hardware Hash (HWID) and uploading it to your Intune tenant, effectively "converting" an existing device into an Autopilot-ready device. 

**Note for Version 2:** This updated solution now uses native CIM/WMI queries to extract the hardware hash, entirely removing the dependency on installing the external `Get-WindowsAutoPilotInfo` module.

## Purpose & Benefits

This project solves the challenge of enroling existing, already-deployed Windows devices into Windows Autopilot. Manually exporting and importing hardware hashes is time-consuming. This solution provides two PowerShell scripts to automate the process:

* **API Creation Script -** A one-time setup script that creates an App Registration in Entra ID (Azure AD) with the specific Graph API permissions needed to import devices.
* **Ingestion Script (V2) -** A template script you deploy to your endpoints (via RMM, Intune, GPO, etc.). This script securely captures the device's local hardware hash via native CIM commands and sends it directly to Intune using the new API.

---

## Prerequisites - For API Setup

* Global Administrator permissions in your Microsoft 365 tenant (for the one-time API setup).
* PowerShell 5.1 or later.
* The latest `Microsoft.Graph` PowerShell module installed on the admin machine where you run the setup script.

---

## Setup and Configuration

### Step 1: Set up the API

This script configures the necessary API permissions in Entra ID.

1.  Run the HWID API Creation Tool Script from this repository.
2.  You will be prompted to sign in with a Global Admin account.
3.  When prompted by the browser, accept the permissions and check the "Consent on behalf of your organisation" box.
4.  The script creates a new App Registration named "Autopilot HWID Ingestion".
5.  A Client Secret is automatically generated and exported to `C:\temp\AppRegistration_Secrets.csv` by default. **Secure this secret value immediately**; you will need it in Step 3.

<img width="888" height="502" alt="image" src="https://github.com/user-attachments/assets/13abd7cd-04e6-4d90-bff4-1c48191247db" />

### Step 2: Grant Admin Consent

You now need to accept admin consent within the Entra Portal.

1.  Navigate to Entra ID [https://entra.microsoft.com].
2.  Go to **Identity > Applications > App Registrations > All Applications**.
3.  Open the new "Autopilot HWID Ingestion" app.
4.  Select the **API Permissions** blade.
5.  Ensure all permissions have a green checkmark under the "Status" column. If not, click the "Grant admin consent for [Your Tenant]" button.

*Tip: You can also use this URL (replace with your values) to force the consent prompt: `https://login.microsoftonline.com/{tenantId}/adminconsent?client_id={clientID}`*

### Step 3: Gather Tenant ID, App ID & Secret

You now need three pieces of information for the client script.

1.  From the Overview page of the "Autopilot HWID Ingestion" app, copy the:
    * `Application (client) ID`
    * `Directory (tenant) ID`
2.  From your saved `AppRegistration_Secrets.csv` (or from the Certificates & secrets blade if you created one manually), copy the `Secret Value`.

### Step 4: Configure the Ingestion Script

The `Autopilot HWID Ingestion - Template.ps1` file on this Repo is the script you are deploying to the actual Endpoints.

1.  Open the V2 Ingestion script in a code editor.
2.  Update the Configuration block at the top of the script with the Tenant ID, App ID, and App Secret you just collected. You can also define your target Autopilot Group Tag here *(This is the Device Tag you will see on Intune itself, useful for multi-site/profile Autopilot setups.)*
3.  Save this configured script.

### Step 5: Deploy to Machines

Deploy the configured `.ps1` script using your preferred endpoint management tool (Intune, RMM, GPO, SCCM, etc.).

**Warning:** The deployment must be run as the **SYSTEM** account or a local administrator. The V2 script queries restricted CIM namespaces (`root/cimv2/mdm/dmmap`) to extract the hardware hash. It will fail with an "Access denied" error if run as a standard logged-in user. 

The Version 2 script includes a built-in elevation check and will terminate safely if administrative privileges are not detected.

**Security Recommendation:** This script uses App Secret with API access into your tenant, make sure your RMM removes the file after and routinely change/delete the App Secret or swap to a Cert-based method. Some RMM's may allow you to use Environment Variables to call a secret instead of using plaintext.

---

## What Happens Next?

After the script successfully runs on a target device, its hardware hash will appear in the Intune portal within a few minutes (Microsoft Intune can take up to 60 minutes to refresh)

You can find it under: **Devices > Device Onboarding > Enrollment > Devices** (within the "Windows Autopilot Devices" blade).

Once the device appears, you can assign it to a group and target it with an Autopilot Deployment. Recommend you use Group Tags to target Autopilot Devices.

Once imported and all Autopilot/Intune is setup; fully reset the device (If you have it to hand, recommend USB Reinstall as it's quicker with a fresh image) and Autopilot should boot through as long as the device has internet.