# Kabristan Committee Management System — Project Master Context

## 1. Project Overview

The Kabristan Committee Management System is a private, bilingual mobile application for a community-based graveyard management committee in Pakistan.

The committee is a group of responsible individuals who collectively manage a community graveyard. It collects financial contributions from registered families to support the purchase, maintenance, and management of graveyard land and facilities. Family membership information, contributions, membership cards, and burial records currently need to be managed systematically.

Objective: digitize these operations through a secure mobile application.

The final product must be a real installed mobile application for Android and iOS, not a website or PWA.

## 2. Project Objectives

- Digitize family registration and membership records.
- Maintain individual records of family members.
- Manage family membership cards.
- Record monthly, annual, and advance contributions.
- Track outstanding and advance payments.
- Generate payment receipts.
- Manage non-member burial payments.
- Maintain deceased persons' and burial records.
- Track family changes resulting from marriages.
- Maintain transparent financial records.
- Provide different access permissions to committee personnel.
- Preserve historical records for future reference.
- Protect all personal and financial information.

## 3. Membership Structure

- The committee follows a family-based membership model.
- Each registered family receives a unique membership card and identification number.
- A family can contain multiple individuals: father, mother, sons, daughters, and other registered dependents.
- Each person has an individual record linked to their family.
- The application must distinguish between a family record and individual family-member records.

### Family changes

- **Married son:** a son who marries and sets up a separate household may leave his father's family membership and receive a new membership card. His previous family relationship remains in the historical record.
- **Married daughter:** a daughter who marries may leave her original family membership and become associated with another family. The transfer must be recorded and historical relationships preserved.
- Records must never be permanently deleted because a family relationship changes.

## 4. Financial Contribution Structure

Official amounts:

- Monthly equivalent: PKR 200 per family.
- Annual contribution: PKR 2,400 per family.
- Families may pay annually.
- Families may pay for two or three years in advance.
- Monthly payments are not compulsory.

### Outstanding contributions

The committee follows its constitution for payment allowances, outstanding dues, and burial eligibility. The application must support:

- Previous payments.
- Outstanding contributions.
- Advance payments.
- Multiple-year payments.
- Payment history.
- Payment verification.
- Constitution-defined allowance periods.

The exact grace-period and arrears calculations must be confirmed with the committee chairman.

The application must not automatically reject burial eligibility because a family has an outstanding balance. Financial status and burial eligibility are separate concepts.

## 5. Non-Member Burial Policy

Families without a membership card may still request burial services.

- The family pays a one-time amount set by the committee.
- The payment covers only that person's burial and does not create permanent membership.
- The payment is recorded separately from ordinary membership contributions.
- A burial record is created for the deceased person.

**The amount has not been finalized.**

## 6. Payment Management

Every financial transaction must be individually recorded and traceable. The application maintains:

- Unique transaction ID.
- Unique receipt number.
- Family membership reference, where applicable.
- Payment category.
- Amount received.
- Payment date.
- Payment method.
- Collecting committee officer.
- Verification status.
- Relevant contribution period.
- Transaction history.

Payment categories:

1. Family membership contributions.
2. Voluntary donations.
3. Non-member burial payments.
4. Other committee-approved financial collections.

Original financial transactions must not be silently overwritten or deleted. Corrections are recorded through authorized adjustment or reversal entries.

## 7. Burial Record Management

Burial records cover both registered and non-registered families. Each record may include:

- Deceased person's name.
- Associated family, if registered.
- Membership card reference, if applicable.
- Burial date.
- Burial location or grave reference.
- Payment information.
- Committee approval information.
- Notes.
- Historical references.

Burial records are preserved for long-term reference.

## 8. Committee Administration and Access Control

The application is for a limited number of authorized committee personnel. It is not for public access.

Proposed roles (**not yet approved**):

- Super Admin (highest authority).
- Committee Admin.
- Treasurer.
- Collection Officer.
- General Committee Member.

The final role-based access structure will be discussed by the project owner with the committee chairman. The application must eventually support granular permissions for viewing, creating, modifying, approving, and managing records.

## 9. Security and Privacy Requirements

Sensitive data includes family information, individual member records, membership details, contributions, payment histories, burial records, and committee administrative information.

Expected initial scale: approximately 250–300 people.

Required considerations:

- Authorized user accounts only.
- Secure authentication.
- Role-based access control.
- Multi-factor authentication for privileged accounts.
- Database-level authorization.
- Encryption in transit.
- Protection of sensitive information.
- Secure financial transaction handling.
- Audit logs.
- Independent encrypted backups.
- Backup restoration testing.
- Secure session management.
- Revocation of access from lost devices.

Family and financial records must never be publicly accessible. Collect only information necessary for committee operations.

## 10. Mobile Application Requirements

- An installed app is mandatory, for Android and iOS.
- Used by a small group of authorized personnel.
- Public Play Store or App Store discovery is not required. Private distribution is preferred.
- Android: signed APK distribution is a possible approach.
- iOS: an Apple-approved signing and distribution method must be selected.
- The project owner does not own a Mac. Development happens on Windows, with cloud macOS build infrastructure used for iOS compilation and signing.

## 11. Proposed Technical Architecture

*Proposed, to be validated during implementation.*

- Mobile frontend: Flutter and Dart.
- Backend: Supabase.
- Database: PostgreSQL.
- Authentication: Supabase Auth.
- Database security: PostgreSQL Row-Level Security, strict access policies, protected server-side financial operations.
- Development environment: Windows laptop.
- Android build: Flutter Android build tools.
- iOS build: cloud macOS build service such as Codemagic.
- Source control: private Git repository.

## 12. Application Language

The app supports two languages: English (left-to-right) and Urdu (right-to-left). Proper localization and layout direction are required.

All important elements are available in both languages: navigation, dashboard, forms, family information, payment information, membership cards, receipts, burial records, reports, notifications, and validation messages.

The project owner communicates with AI assistants in English.

## 13. Visual Identity and UI Direction

Approved theme: **Emerald & Ivory — Modern Light Mode.**

| Role | Hex |
|---|---|
| Emerald Green | #116B50 |
| Deep Emerald | #0B4D3B |
| Ivory Background | #F8FAF7 |
| White Cards | #FFFFFF |
| Gold Accent | #C8A768 |
| Main Text | #263B35 |
| Secondary Text | #728079 |

Design should feel modern, professional, respectful, clean, trustworthy, accessible, and suited to a charitable community organization.

Approved dashboard reference contains: committee branding with mosque illustration; administrator welcome banner; registered family statistics; annual collection statistics; pending account statistics; burial record statistics; quick action tiles; recent payment records; five-item bottom navigation.

## 14. Main Application Modules

1. Authentication and user management
2. Dashboard
3. Family registration
4. Family-member management
5. Membership card management
6. Family transfers
7. Payment collection
8. Payment history
9. Receipt generation
10. Burial registration
11. Burial history
12. Financial reports
13. Committee administration
14. Role-based access control
15. Audit logs
16. Application settings
17. Urdu and English localization

## 15. Development Philosophy

- Data integrity, financial transparency, security, privacy, long-term record preservation.
- Simplicity for committee personnel.
- Low operating and maintenance costs; avoid unnecessary infrastructure and expensive technology.
- Reliability and future scalability.
- Develop and test with **fictional data** before importing any real committee information.

## 16. Unresolved Decisions (do not invent or assume)

1. Final role-based access permissions.
2. Exact constitutional payment allowance and grace-period calculations.
3. Non-member burial charges.
4. Exact burial approval procedure.
5. Financial verification and cash-handover procedure.
6. Final family transfer approval procedure.
7. Apple private distribution method.
8. Final backup retention and operational budget.

Business rules are to be confirmed with the committee chairman.

**Contributors and AI assistants must distinguish confirmed requirements (sections 1–10, 12–15), proposed solutions (section 11 and anything marked proposed), and unresolved decisions (section 16).**

## 17. Overall Vision

A reliable, secure, bilingual mobile management system that lets the Kabristan Committee keep accurate records of registered families, individual members, membership cards, financial contributions, non-member burial payments, family changes, and burial history. It replaces fragmented manual record-keeping with a centralized, traceable, secure digital system that serves the committee for many years while protecting families' privacy, financial information, and historical records.
