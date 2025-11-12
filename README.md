# Automated HWID Import for Autopilot

This tool automates the process of capturing a device's Hardware Hash (HWID) and uploading it to your Intune tenant, effectively "converting" an existing device into an Autopilot-ready device.

## Purpose & Benefits

This project solves the challenge of enrolling existing, already-deployed Windows devices into Windows Autopilot. Manually exporting and importing hardware hashes is time-consuming. This solution provides two PowerShell scripts to automate the process:

**API Creation Script:** A one-time setup script that creates an App Registration in Entra ID (Azure AD) with the specific Graph API permissions needed to import devices.

**Ingestion Script:** A template script you deploy to your endpoints (via RMM, Intune, GPO, etc.). This script captures the device's local hardware hash and sends it directly to Intune via the new API.

### Key Benefits

**Automate Enrollment:** Eliminates the need for manual Get-WindowsAutoPilotInfo exports and CSV uploads.

**Tenant Lock:** Binds the device's hardware (motherboard) to your tenant.

**Streamline Re-provisioning:** Once a device is imported, you can assign an Autopilot Deployment Profile. After a PC reset (or drive replacement), the device will automatically enter your company's Autopilot Out-of-Box Experience (OOBE) every time.

## Prerequisites

Global Administrator permissions in your Microsoft 365 tenant (for the one-time API setup).

PowerShell 5.1 or later.

The latest Microsoft.Graph PowerShell module installed on the admin machine where you run the setup script.

## Setup and Configuration

### Step 1: Set up API:

This script configures the necessary API permissions in Entra ID.

Run the HWID API Creation Tool Script from this Repo

You will be prompted to sign in with a Global Admin account.

When prompted by the browser, accept the permissions and check the "Consent on behalf of your organization" box.

The script creates a new App Registration named "Autopilot HWID Ingestion".

A Client Secret is automatically generated and exported to C:\temp\AppRegistration_Secrets.csv by default. **Secure this secret value immediately**; you will need it in Step 3.

<img width="888" height="502" alt="image" src="https://github.com/user-attachments/assets/13abd7cd-04e6-4d90-bff4-1c48191247db" />

### Step 2: Granting Admin Consent:

You now to accept admin consent within the Entra Portal.

Navigate to Entra ID [https://entra.microsoft.com].

Go to Identity > Applications > App Registrations > All Applications.

Open the new "Autopilot HWID Ingestion" app.

Select the API Permissions blade.

Ensure all permissions have a green checkmark under the "Status" column. If not, click the "Grant admin consent for [Your Tenant]" button.

Tip: You can also use this URL (replace with your values) to force the consent prompt: `https://login.microsoftonline.com/{tenantId}/adminconsent?client_id={clientID}`

### Step 3: Tenant ID, App ID & Secret

You now need three pieces of information for the client script.

1. From the Overview page of the "Autopilot HWID Ingestion" app, copy the:

    `Application (client) ID`

    `Directory (tenant) ID`

2. From your saved AppRegistration_Secrets.csv (or from the Certificates & secrets blade if you created one manually), copy the `Secret Value`.

### Step 5: Configure the Ingestion Script

This is the script you will deploy to your target devices.

Open the `Autopilot HWID Ingestion - Template.ps1` script in a code editor.

Update lines 1, 2, and 3 with the Tenant ID, App ID, and App Secret (the Secret's Value) you just collected.

Save this configured script.

### Step 6: Deploy to Machines

Deploy the configured .ps1 script using your preferred endpoint management tool (Intune, RMM, GPO, SCCM, etc.).

**Warning: The deployment must be run as the SYSTEM account or a local administrator. It will fail if run as a standard logged-in user because it requires elevated permissions to read the hardware hash from WMI.**

## What Happens Next?

After the script successfully runs on a target device, its hardware hash will appear in the Intune portal within a few minutes.

You can find it under: Devices > Enroll devices > Windows enrollment > Devices (within the "Windows Autopilot Devices" blade).

Once the device appears, you can assign it to a group and target it with an Autopilot Deployment Profile and an Enrollment Status Page (ESP) profile to control the OOBE.
