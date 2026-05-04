# Project description: Matrix Server as a communication platform for the DMI

## Summary

The project aims to design, implement and deploy a production-ready, self-hosted Matrix Server as infrastructure for the DMI at the University of Basel. The system will be built on the Matrix open communication protocol and serve as a privacy-focused, in-house alternative to the current use of Discord, which is a proprietary, externally hosted platform with no integration into university identity management.

The result will be a fully operational service, running on a VM provided by the ITS, with integration into the Switch-edu-id authentication infrastructure already used. Further the project will include a complete hand-off documentation enabling IT Services or other groups to maintain and extend the system.

## Technical Scope 

The system will include the following components, deployed as a Docker container on a single VM:
- Synapse (Matrix homeserver) with a PostgreSQL database backend
- Element Web (self-hosted matrix web client)
  - Note: The server could be used without this, but it allows us to preconfigure the client for users and make onboarding easier, while still giving them the opportunity to use their own Matrix client.
- Nginx reverse proxy with TLS (either something like Let's Encrypt or maybe unibas has their own Certificate authority?)
- Mautrix-discord (Bridge to discord to migrate / mirror)
  - Note: Technically optional, but we want to include it
- Integration to Switch-edu-id, so users can authenticate their account using existing credentials & our server never needs to authenticate users itself

**Optional / Stretch goals:**
- Coturn (TURN/STUN server for voice & video calls)
- Prometheus and Grafana for operational monitoring / alerting
- Website / User guide

## Deliverables
- Containerised deployment stack (Docker Compose)
  - Synapse homeserver with PostreSQL, TLS & rate limiting
  - Switch-edu-id integration
  - Element web client instance 
  - Discord-Matrix bridge
  - OPTIONAL: Prometheus metrics collection & Grafana dashboard
- Playbook for ITS (e.g. Ansible) for setup & maintaining
- Automated backup procedure & tested restore process
- OPTIONAL: User guide in form of a website (similar to install guide for e.g. GlobalProtect etc.)

## Needs 
- Access to Server / VM 
  - Also: Needs to be accessible from internet (or at least university internally / via VPN)
  - Have a domain (e.g. dmi.matrix.unibas.ch or something similar)
- Access / Information about Switch-edu-id for integration 
- Access / Information about TLS certificates for HTTPS
- OPTIONAL: Access to a unibas website to host the User guide

# Feedback 

Fragen:
- Admin UI o.ä.
- Punkte in Räume von Gruppen posten etc.
- Datenschutz / Moderation

