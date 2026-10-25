export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      audit_events: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          detail: Json
          id: number
          target_id: string | null
          workspace_id: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          detail?: Json
          id?: never
          target_id?: string | null
          workspace_id?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          detail?: Json
          id?: never
          target_id?: string | null
          workspace_id?: string | null
        }
        Relationships: []
      }
      content_roles: {
        Row: {
          created_at: string
          granted_by: string | null
          role: Database["public"]["Enums"]["content_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          granted_by?: string | null
          role: Database["public"]["Enums"]["content_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          granted_by?: string | null
          role?: Database["public"]["Enums"]["content_role"]
          user_id?: string
        }
        Relationships: []
      }
      invitation_emails: {
        Row: {
          created_at: string
          error: string | null
          id: number
          invitation_id: string
          provider: string
          provider_message_id: string | null
          sent_by: string
          status: string
          to_email: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          error?: string | null
          id?: never
          invitation_id: string
          provider?: string
          provider_message_id?: string | null
          sent_by: string
          status: string
          to_email: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          error?: string | null
          id?: never
          invitation_id?: string
          provider?: string
          provider_message_id?: string | null
          sent_by?: string
          status?: string
          to_email?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "invitation_emails_invitation_id_fkey"
            columns: ["invitation_id"]
            isOneToOne: false
            referencedRelation: "workspace_invitations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invitation_emails_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_admins: {
        Row: {
          granted_at: string
          user_id: string
        }
        Insert: {
          granted_at?: string
          user_id: string
        }
        Update: {
          granted_at?: string
          user_id?: string
        }
        Relationships: []
      }
      product_access: {
        Row: {
          level: string
          product: string
          updated_at: string
          updated_by: string | null
          user_id: string
          workspace_id: string
        }
        Insert: {
          level: string
          product: string
          updated_at?: string
          updated_by?: string | null
          user_id: string
          workspace_id: string
        }
        Update: {
          level?: string
          product?: string
          updated_at?: string
          updated_by?: string | null
          user_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_access_workspace_id_user_id_fkey"
            columns: ["workspace_id", "user_id"]
            isOneToOne: false
            referencedRelation: "workspace_members"
            referencedColumns: ["workspace_id", "user_id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          display_name: string | null
          id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_name?: string | null
          id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_name?: string | null
          id?: string
          updated_at?: string
        }
        Relationships: []
      }
      team_members: {
        Row: {
          added_at: string
          added_by: string | null
          team_id: string
          user_id: string
          workspace_id: string
        }
        Insert: {
          added_at?: string
          added_by?: string | null
          team_id: string
          user_id: string
          workspace_id: string
        }
        Update: {
          added_at?: string
          added_by?: string | null
          team_id?: string
          user_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "team_members_team_id_workspace_id_fkey"
            columns: ["team_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "team_members_workspace_id_user_id_fkey"
            columns: ["workspace_id", "user_id"]
            isOneToOne: false
            referencedRelation: "workspace_members"
            referencedColumns: ["workspace_id", "user_id"]
          },
        ]
      }
      teams: {
        Row: {
          created_at: string
          created_by: string
          id: string
          name: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          name: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          name?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "teams_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_actions: {
        Row: {
          assessment_id: string | null
          completed_at: string | null
          completed_by: string | null
          completion_note: string | null
          created_at: string
          created_by: string
          detail: string | null
          due_on: string | null
          id: string
          incursion_id: string | null
          owner_id: string | null
          site_id: string
          status: string
          step_key: string | null
          title: string
          workspace_id: string
        }
        Insert: {
          assessment_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          completion_note?: string | null
          created_at?: string
          created_by: string
          detail?: string | null
          due_on?: string | null
          id: string
          incursion_id?: string | null
          owner_id?: string | null
          site_id: string
          status?: string
          step_key?: string | null
          title: string
          workspace_id: string
        }
        Update: {
          assessment_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          completion_note?: string | null
          created_at?: string
          created_by?: string
          detail?: string | null
          due_on?: string | null
          id?: string
          incursion_id?: string | null
          owner_id?: string | null
          site_id?: string
          status?: string
          step_key?: string | null
          title?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_actions_assessment_id_workspace_id_fkey"
            columns: ["assessment_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_assessments"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_actions_incursion_fk"
            columns: ["incursion_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_incursions"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_actions_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_actions_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_actions_workspace_id_owner_id_fkey"
            columns: ["workspace_id", "owner_id"]
            isOneToOne: false
            referencedRelation: "workspace_members"
            referencedColumns: ["workspace_id", "user_id"]
          },
        ]
      }
      vv_assessment_results: {
        Row: {
          assessment_id: string
          result_id: string
          workspace_id: string
        }
        Insert: {
          assessment_id: string
          result_id: string
          workspace_id: string
        }
        Update: {
          assessment_id?: string
          result_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_assessment_results_assessment_id_workspace_id_fkey"
            columns: ["assessment_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_assessments"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_assessment_results_result_id_workspace_id_fkey"
            columns: ["result_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_results"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_assessment_versions: {
        Row: {
          assessment_id: string
          author_id: string
          author_role: string
          consequence: number
          factors: Json
          final_level: string
          likelihood: number
          matrix_level: string
          matrix_version: string
          override_reason: string | null
          rationale: string
          reason: string | null
          recorded_at: string
          version: number
          workspace_id: string
        }
        Insert: {
          assessment_id: string
          author_id: string
          author_role: string
          consequence: number
          factors?: Json
          final_level: string
          likelihood: number
          matrix_level: string
          matrix_version: string
          override_reason?: string | null
          rationale: string
          reason?: string | null
          recorded_at?: string
          version: number
          workspace_id: string
        }
        Update: {
          assessment_id?: string
          author_id?: string
          author_role?: string
          consequence?: number
          factors?: Json
          final_level?: string
          likelihood?: number
          matrix_level?: string
          matrix_version?: string
          override_reason?: string | null
          rationale?: string
          reason?: string | null
          recorded_at?: string
          version?: number
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_assessment_versions_assessment_id_workspace_id_fkey"
            columns: ["assessment_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_assessments"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_assessments: {
        Row: {
          created_at: string
          created_by: string
          current_version: number
          id: string
          site_id: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          current_version?: number
          id: string
          site_id: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          current_version?: number
          id?: string
          site_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_assessments_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_assessments_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_attachment_events: {
        Row: {
          action: string
          actor_id: string | null
          actor_role: string | null
          attachment_id: string
          detail: Json
          id: number
          recorded_at: string
          workspace_id: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          actor_role?: string | null
          attachment_id: string
          detail?: Json
          id?: never
          recorded_at?: string
          workspace_id: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          actor_role?: string | null
          attachment_id?: string
          detail?: Json
          id?: never
          recorded_at?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_attachment_events_attachment_id_workspace_id_fkey"
            columns: ["attachment_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_attachments"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_attachments: {
        Row: {
          caption: string | null
          capture_source: string
          captured_at: string | null
          derived_from: string | null
          file_name: string
          id: string
          kind: string
          mime_type: string
          received_at: string
          record_id: string
          record_type: string
          sha256_reported: string
          sha256_stored: string | null
          site_id: string
          size_bytes: number
          status: string
          storage_path: string
          uploaded_by: string
          uploaded_role: string
          verified_at: string | null
          workspace_id: string
        }
        Insert: {
          caption?: string | null
          capture_source: string
          captured_at?: string | null
          derived_from?: string | null
          file_name: string
          id: string
          kind: string
          mime_type: string
          received_at?: string
          record_id: string
          record_type: string
          sha256_reported: string
          sha256_stored?: string | null
          site_id: string
          size_bytes: number
          status?: string
          storage_path: string
          uploaded_by: string
          uploaded_role: string
          verified_at?: string | null
          workspace_id: string
        }
        Update: {
          caption?: string | null
          capture_source?: string
          captured_at?: string | null
          derived_from?: string | null
          file_name?: string
          id?: string
          kind?: string
          mime_type?: string
          received_at?: string
          record_id?: string
          record_type?: string
          sha256_reported?: string
          sha256_stored?: string | null
          site_id?: string
          size_bytes?: number
          status?: string
          storage_path?: string
          uploaded_by?: string
          uploaded_role?: string
          verified_at?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_attachments_derived_from_fkey"
            columns: ["derived_from"]
            isOneToOne: false
            referencedRelation: "vv_attachments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_attachments_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_attachments_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_council_taxa: {
        Row: {
          active: boolean
          common_name: string | null
          created_at: string
          created_by: string
          id: string
          scientific_name: string
          workspace_id: string
        }
        Insert: {
          active?: boolean
          common_name?: string | null
          created_at?: string
          created_by: string
          id: string
          scientific_name: string
          workspace_id: string
        }
        Update: {
          active?: boolean
          common_name?: string | null
          created_at?: string
          created_by?: string
          id?: string
          scientific_name?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_council_taxa_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_council_trap_types: {
        Row: {
          active: boolean
          created_at: string
          created_by: string
          description: string | null
          id: string
          name: string
          workspace_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          created_by: string
          description?: string | null
          id: string
          name: string
          workspace_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          created_by?: string
          description?: string | null
          id?: string
          name?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_council_trap_types_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_deployments: {
        Row: {
          created_by: string
          end_note: string | null
          end_reason: string | null
          ended_at: string | null
          ended_by: string | null
          id: string
          latitude: number | null
          longitude: number | null
          placement: string | null
          recorded_at: string
          responsible_officer: string | null
          site_id: string
          started_at: string
          trap_id: string
          visit_interval_days: number
          workspace_id: string
        }
        Insert: {
          created_by: string
          end_note?: string | null
          end_reason?: string | null
          ended_at?: string | null
          ended_by?: string | null
          id: string
          latitude?: number | null
          longitude?: number | null
          placement?: string | null
          recorded_at?: string
          responsible_officer?: string | null
          site_id: string
          started_at: string
          trap_id: string
          visit_interval_days?: number
          workspace_id: string
        }
        Update: {
          created_by?: string
          end_note?: string | null
          end_reason?: string | null
          ended_at?: string | null
          ended_by?: string | null
          id?: string
          latitude?: number | null
          longitude?: number | null
          placement?: string | null
          recorded_at?: string
          responsible_officer?: string | null
          site_id?: string
          started_at?: string
          trap_id?: string
          visit_interval_days?: number
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_deployments_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_deployments_trap_id_workspace_id_fkey"
            columns: ["trap_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_traps"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_deployments_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_deployments_workspace_id_responsible_officer_fkey"
            columns: ["workspace_id", "responsible_officer"]
            isOneToOne: false
            referencedRelation: "workspace_members"
            referencedColumns: ["workspace_id", "user_id"]
          },
        ]
      }
      vv_events: {
        Row: {
          actor_id: string | null
          actor_role: string | null
          detail: Json
          id: number
          kind: string
          record_id: string
          record_type: string
          recorded_at: string
          workspace_id: string
        }
        Insert: {
          actor_id?: string | null
          actor_role?: string | null
          detail?: Json
          id?: never
          kind: string
          record_id: string
          record_type: string
          recorded_at?: string
          workspace_id: string
        }
        Update: {
          actor_id?: string | null
          actor_role?: string | null
          detail?: Json
          id?: never
          kind?: string
          record_id?: string
          record_type?: string
          recorded_at?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_events_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_exports: {
        Row: {
          counts: Json
          created_at: string
          created_by: string
          created_role: string
          file_name: string
          format_version: string
          id: string
          kind: string
          scope: Json
          sha256: string
          size_bytes: number
          workspace_id: string
        }
        Insert: {
          counts?: Json
          created_at?: string
          created_by: string
          created_role: string
          file_name: string
          format_version: string
          id: string
          kind: string
          scope?: Json
          sha256: string
          size_bytes: number
          workspace_id: string
        }
        Update: {
          counts?: Json
          created_at?: string
          created_by?: string
          created_role?: string
          file_name?: string
          format_version?: string
          id?: string
          kind?: string
          scope?: Json
          sha256?: string
          size_bytes?: number
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_exports_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_external_refs: {
        Row: {
          created_at: string
          created_by: string
          external_id: string
          id: string
          note: string | null
          record_id: string
          record_type: string
          removed_at: string | null
          removed_by: string | null
          removed_reason: string | null
          system: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          external_id: string
          id: string
          note?: string | null
          record_id: string
          record_type: string
          removed_at?: string | null
          removed_by?: string | null
          removed_reason?: string | null
          system: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          external_id?: string
          id?: string
          note?: string | null
          record_id?: string
          record_type?: string
          removed_at?: string | null
          removed_by?: string | null
          removed_reason?: string | null
          system?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_external_refs_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_incursion_findings: {
        Row: {
          added_at: string
          added_by: string
          incursion_id: string
          result_id: string
          workspace_id: string
        }
        Insert: {
          added_at?: string
          added_by: string
          incursion_id: string
          result_id: string
          workspace_id: string
        }
        Update: {
          added_at?: string
          added_by?: string
          incursion_id?: string
          result_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_incursion_findings_incursion_id_workspace_id_fkey"
            columns: ["incursion_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_incursions"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_incursion_findings_result_id_workspace_id_fkey"
            columns: ["result_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_results"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_incursion_sites: {
        Row: {
          added_at: string
          added_by: string
          incursion_id: string
          site_id: string
          workspace_id: string
        }
        Insert: {
          added_at?: string
          added_by: string
          incursion_id: string
          site_id: string
          workspace_id: string
        }
        Update: {
          added_at?: string
          added_by?: string
          incursion_id?: string
          site_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_incursion_sites_incursion_id_workspace_id_fkey"
            columns: ["incursion_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_incursions"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_incursion_sites_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_incursion_steps: {
        Row: {
          decided_at: string | null
          decided_by: string | null
          incursion_id: string
          note: string | null
          sort_order: number
          status: string
          step_key: string
          workspace_id: string
        }
        Insert: {
          decided_at?: string | null
          decided_by?: string | null
          incursion_id: string
          note?: string | null
          sort_order: number
          status?: string
          step_key: string
          workspace_id: string
        }
        Update: {
          decided_at?: string | null
          decided_by?: string | null
          incursion_id?: string
          note?: string | null
          sort_order?: number
          status?: string
          step_key?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_incursion_steps_incursion_id_workspace_id_fkey"
            columns: ["incursion_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_incursions"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_incursions: {
        Row: {
          council_taxon_id: string | null
          created_at: string
          created_by: string
          id: string
          lead_officer_id: string | null
          opened_at: string
          reference: string
          response_area: Json | null
          site_id: string
          status: string
          taxon_id: string | null
          title: string
          updated_at: string
          updated_by: string | null
          workspace_id: string
        }
        Insert: {
          council_taxon_id?: string | null
          created_at?: string
          created_by: string
          id: string
          lead_officer_id?: string | null
          opened_at?: string
          reference: string
          response_area?: Json | null
          site_id: string
          status?: string
          taxon_id?: string | null
          title: string
          updated_at?: string
          updated_by?: string | null
          workspace_id: string
        }
        Update: {
          council_taxon_id?: string | null
          created_at?: string
          created_by?: string
          id?: string
          lead_officer_id?: string | null
          opened_at?: string
          reference?: string
          response_area?: Json | null
          site_id?: string
          status?: string
          taxon_id?: string | null
          title?: string
          updated_at?: string
          updated_by?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_incursions_council_taxon_id_workspace_id_fkey"
            columns: ["council_taxon_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_council_taxa"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_incursions_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_incursions_taxon_id_fkey"
            columns: ["taxon_id"]
            isOneToOne: false
            referencedRelation: "vv_taxa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_incursions_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_incursions_workspace_id_lead_officer_id_fkey"
            columns: ["workspace_id", "lead_officer_id"]
            isOneToOne: false
            referencedRelation: "workspace_members"
            referencedColumns: ["workspace_id", "user_id"]
          },
        ]
      }
      vv_library_images: {
        Row: {
          added_at: string
          added_by: string
          caption: string | null
          credit: string
          id: string
          licence: string
          sort_order: number
          source_url: string
          storage_path: string
          version_id: string
        }
        Insert: {
          added_at?: string
          added_by: string
          caption?: string | null
          credit: string
          id: string
          licence: string
          sort_order?: number
          source_url: string
          storage_path: string
          version_id: string
        }
        Update: {
          added_at?: string
          added_by?: string
          caption?: string | null
          credit?: string
          id?: string
          licence?: string
          sort_order?: number
          source_url?: string
          storage_path?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_library_images_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "vv_library_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_library_notes: {
        Row: {
          created_at: string
          created_by: string
          id: string
          kind: string
          note: string
          taxon_id: string | null
          trap_type_id: string | null
          updated_at: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id: string
          kind: string
          note: string
          taxon_id?: string | null
          trap_type_id?: string | null
          updated_at?: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          kind?: string
          note?: string
          taxon_id?: string | null
          trap_type_id?: string | null
          updated_at?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_library_notes_taxon_id_fkey"
            columns: ["taxon_id"]
            isOneToOne: false
            referencedRelation: "vv_taxa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_library_notes_trap_type_id_fkey"
            columns: ["trap_type_id"]
            isOneToOne: false
            referencedRelation: "vv_trap_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_library_notes_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_library_versions: {
        Row: {
          author_id: string | null
          content: Json
          created_at: string
          id: string
          kind: string
          published_at: string | null
          publisher_id: string | null
          review_note: string | null
          reviewed_at: string | null
          reviewer_id: string | null
          sources: Json
          status: Database["public"]["Enums"]["kp_status"]
          taxon_id: string | null
          trap_type_id: string | null
          version: number
        }
        Insert: {
          author_id?: string | null
          content: Json
          created_at?: string
          id?: string
          kind: string
          published_at?: string | null
          publisher_id?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewer_id?: string | null
          sources?: Json
          status?: Database["public"]["Enums"]["kp_status"]
          taxon_id?: string | null
          trap_type_id?: string | null
          version: number
        }
        Update: {
          author_id?: string | null
          content?: Json
          created_at?: string
          id?: string
          kind?: string
          published_at?: string | null
          publisher_id?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewer_id?: string | null
          sources?: Json
          status?: Database["public"]["Enums"]["kp_status"]
          taxon_id?: string | null
          trap_type_id?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "vv_library_versions_taxon_id_fkey"
            columns: ["taxon_id"]
            isOneToOne: false
            referencedRelation: "vv_taxa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_library_versions_trap_type_id_fkey"
            columns: ["trap_type_id"]
            isOneToOne: false
            referencedRelation: "vv_trap_types"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_notifications: {
        Row: {
          contact_id: string | null
          id: string
          incursion_id: string
          kind: string
          method: string
          note: string | null
          notified_at: string
          recipient: string
          recorded_at: string
          recorded_by: string
          recorded_role: string
          reference: string | null
          workspace_id: string
        }
        Insert: {
          contact_id?: string | null
          id: string
          incursion_id: string
          kind: string
          method: string
          note?: string | null
          notified_at: string
          recipient: string
          recorded_at?: string
          recorded_by: string
          recorded_role: string
          reference?: string | null
          workspace_id: string
        }
        Update: {
          contact_id?: string | null
          id?: string
          incursion_id?: string
          kind?: string
          method?: string
          note?: string | null
          notified_at?: string
          recipient?: string
          recorded_at?: string
          recorded_by?: string
          recorded_role?: string
          reference?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_notifications_contact_id_workspace_id_fkey"
            columns: ["contact_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_notify_contacts"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_notifications_incursion_id_workspace_id_fkey"
            columns: ["incursion_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_incursions"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_notify_contacts: {
        Row: {
          active: boolean
          created_at: string
          created_by: string
          detail: string | null
          id: string
          kind: string
          name: string
          organisation: string | null
          workspace_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          created_by: string
          detail?: string | null
          id: string
          kind: string
          name: string
          organisation?: string | null
          workspace_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          created_by?: string
          detail?: string | null
          id?: string
          kind?: string
          name?: string
          organisation?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_notify_contacts_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_programme_teams: {
        Row: {
          programme_id: string
          team_id: string
          workspace_id: string
        }
        Insert: {
          programme_id: string
          team_id: string
          workspace_id: string
        }
        Update: {
          programme_id?: string
          team_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_programme_teams_programme_id_workspace_id_fkey"
            columns: ["programme_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_programmes"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_programme_teams_team_id_workspace_id_fkey"
            columns: ["team_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_programmes: {
        Row: {
          created_at: string
          created_by: string
          description: string | null
          ends_on: string | null
          id: string
          name: string
          starts_on: string | null
          status: string
          updated_at: string
          vector_group: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          description?: string | null
          ends_on?: string | null
          id: string
          name: string
          starts_on?: string | null
          status?: string
          updated_at?: string
          vector_group?: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          description?: string | null
          ends_on?: string | null
          id?: string
          name?: string
          starts_on?: string | null
          status?: string
          updated_at?: string
          vector_group?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_programmes_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_result_versions: {
        Row: {
          author_id: string
          author_role: string
          council_taxon_id: string | null
          identified_by: string | null
          lab_reference: string | null
          laboratory: string | null
          method: string | null
          quantity: number | null
          reason: string | null
          recorded_at: string
          result_date: string | null
          result_id: string
          status: string
          taxon_id: string | null
          uncertainty: string | null
          unit: string | null
          version: number
          workspace_id: string
        }
        Insert: {
          author_id: string
          author_role: string
          council_taxon_id?: string | null
          identified_by?: string | null
          lab_reference?: string | null
          laboratory?: string | null
          method?: string | null
          quantity?: number | null
          reason?: string | null
          recorded_at?: string
          result_date?: string | null
          result_id: string
          status: string
          taxon_id?: string | null
          uncertainty?: string | null
          unit?: string | null
          version: number
          workspace_id: string
        }
        Update: {
          author_id?: string
          author_role?: string
          council_taxon_id?: string | null
          identified_by?: string | null
          lab_reference?: string | null
          laboratory?: string | null
          method?: string | null
          quantity?: number | null
          reason?: string | null
          recorded_at?: string
          result_date?: string | null
          result_id?: string
          status?: string
          taxon_id?: string | null
          uncertainty?: string | null
          unit?: string | null
          version?: number
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_result_versions_council_taxon_id_workspace_id_fkey"
            columns: ["council_taxon_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_council_taxa"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_result_versions_result_id_workspace_id_fkey"
            columns: ["result_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_results"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_result_versions_taxon_id_fkey"
            columns: ["taxon_id"]
            isOneToOne: false
            referencedRelation: "vv_taxa"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_results: {
        Row: {
          created_at: string
          created_by: string
          current_version: number
          id: string
          sample_id: string
          site_id: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          current_version?: number
          id: string
          sample_id: string
          site_id: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          current_version?: number
          id?: string
          sample_id?: string
          site_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_results_sample_id_workspace_id_fkey"
            columns: ["sample_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_samples"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_results_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_results_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_samples: {
        Row: {
          created_by: string
          id: string
          method: string
          notes: string | null
          recorded_at: string
          reference: string
          site_id: string
          status: string
          visit_id: string
          workspace_id: string
        }
        Insert: {
          created_by: string
          id: string
          method: string
          notes?: string | null
          recorded_at?: string
          reference: string
          site_id: string
          status?: string
          visit_id: string
          workspace_id: string
        }
        Update: {
          created_by?: string
          id?: string
          method?: string
          notes?: string | null
          recorded_at?: string
          reference?: string
          site_id?: string
          status?: string
          visit_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_samples_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_samples_visit_id_workspace_id_fkey"
            columns: ["visit_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_visits"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_samples_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_site_programmes: {
        Row: {
          programme_id: string
          site_id: string
          workspace_id: string
        }
        Insert: {
          programme_id: string
          site_id: string
          workspace_id: string
        }
        Update: {
          programme_id?: string
          site_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_site_programmes_programme_id_workspace_id_fkey"
            columns: ["programme_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_programmes"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_site_programmes_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_sites: {
        Row: {
          access_instructions: string | null
          created_at: string
          created_by: string
          id: string
          latitude: number | null
          line_1: string | null
          line_2: string | null
          location_description: string | null
          longitude: number | null
          name: string
          postcode: string | null
          reference: string
          status: string
          town: string | null
          updated_at: string
          updated_by: string | null
          uprn: string | null
          workspace_id: string
        }
        Insert: {
          access_instructions?: string | null
          created_at?: string
          created_by: string
          id: string
          latitude?: number | null
          line_1?: string | null
          line_2?: string | null
          location_description?: string | null
          longitude?: number | null
          name: string
          postcode?: string | null
          reference: string
          status?: string
          town?: string | null
          updated_at?: string
          updated_by?: string | null
          uprn?: string | null
          workspace_id: string
        }
        Update: {
          access_instructions?: string | null
          created_at?: string
          created_by?: string
          id?: string
          latitude?: number | null
          line_1?: string | null
          line_2?: string | null
          location_description?: string | null
          longitude?: number | null
          name?: string
          postcode?: string | null
          reference?: string
          status?: string
          town?: string | null
          updated_at?: string
          updated_by?: string | null
          uprn?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_sites_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_stand_downs: {
        Row: {
          decided_at: string
          decided_by: string
          decided_role: string
          id: string
          incursion_id: string
          kind: string
          rationale: string
          recorded_at: string
          workspace_id: string
        }
        Insert: {
          decided_at: string
          decided_by: string
          decided_role: string
          id: string
          incursion_id: string
          kind: string
          rationale: string
          recorded_at?: string
          workspace_id: string
        }
        Update: {
          decided_at?: string
          decided_by?: string
          decided_role?: string
          id?: string
          incursion_id?: string
          kind?: string
          rationale?: string
          recorded_at?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_stand_downs_incursion_id_workspace_id_fkey"
            columns: ["incursion_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_incursions"
            referencedColumns: ["id", "workspace_id"]
          },
        ]
      }
      vv_taxa: {
        Row: {
          checked: boolean
          common_name: string | null
          id: string
          invasive: boolean
          key: string
          scientific_name: string
          sort_order: number
          vector_group: string
        }
        Insert: {
          checked?: boolean
          common_name?: string | null
          id?: string
          invasive?: boolean
          key: string
          scientific_name: string
          sort_order?: number
          vector_group?: string
        }
        Update: {
          checked?: boolean
          common_name?: string | null
          id?: string
          invasive?: boolean
          key?: string
          scientific_name?: string
          sort_order?: number
          vector_group?: string
        }
        Relationships: []
      }
      vv_trap_types: {
        Row: {
          checked: boolean
          description: string | null
          id: string
          key: string
          name: string
          sort_order: number
          vector_group: string
        }
        Insert: {
          checked?: boolean
          description?: string | null
          id?: string
          key: string
          name: string
          sort_order?: number
          vector_group?: string
        }
        Update: {
          checked?: boolean
          description?: string | null
          id?: string
          key?: string
          name?: string
          sort_order?: number
          vector_group?: string
        }
        Relationships: []
      }
      vv_traps: {
        Row: {
          council_trap_type_id: string | null
          created_at: string
          created_by: string
          id: string
          identifier: string
          notes: string | null
          status: string
          trap_type_id: string | null
          updated_at: string
          updated_by: string | null
          workspace_id: string
        }
        Insert: {
          council_trap_type_id?: string | null
          created_at?: string
          created_by: string
          id: string
          identifier: string
          notes?: string | null
          status?: string
          trap_type_id?: string | null
          updated_at?: string
          updated_by?: string | null
          workspace_id: string
        }
        Update: {
          council_trap_type_id?: string | null
          created_at?: string
          created_by?: string
          id?: string
          identifier?: string
          notes?: string | null
          status?: string
          trap_type_id?: string | null
          updated_at?: string
          updated_by?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_traps_council_trap_type_id_workspace_id_fkey"
            columns: ["council_trap_type_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_council_trap_types"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_traps_trap_type_id_fkey"
            columns: ["trap_type_id"]
            isOneToOne: false
            referencedRelation: "vv_trap_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vv_traps_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_visits: {
        Row: {
          created_by: string
          deployment_id: string
          exposure_ended_at: string | null
          exposure_started_at: string | null
          id: string
          not_completed_reason: string | null
          observations: string | null
          occurred_at: string
          officer_id: string
          outcome: string
          recorded_at: string
          site_id: string
          trap_condition: string
          updated_at: string | null
          updated_by: string | null
          workspace_id: string
        }
        Insert: {
          created_by: string
          deployment_id: string
          exposure_ended_at?: string | null
          exposure_started_at?: string | null
          id: string
          not_completed_reason?: string | null
          observations?: string | null
          occurred_at: string
          officer_id: string
          outcome: string
          recorded_at?: string
          site_id: string
          trap_condition: string
          updated_at?: string | null
          updated_by?: string | null
          workspace_id: string
        }
        Update: {
          created_by?: string
          deployment_id?: string
          exposure_ended_at?: string | null
          exposure_started_at?: string | null
          id?: string
          not_completed_reason?: string | null
          observations?: string | null
          occurred_at?: string
          officer_id?: string
          outcome?: string
          recorded_at?: string
          site_id?: string
          trap_condition?: string
          updated_at?: string | null
          updated_by?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_visits_deployment_id_workspace_id_fkey"
            columns: ["deployment_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_deployments"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_visits_site_id_workspace_id_fkey"
            columns: ["site_id", "workspace_id"]
            isOneToOne: false
            referencedRelation: "vv_sites"
            referencedColumns: ["id", "workspace_id"]
          },
          {
            foreignKeyName: "vv_visits_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      vv_workspace_settings: {
        Row: {
          next_incursion_no: number
          next_sample_no: number
          next_site_no: number
          site_prefix: string
          workspace_id: string
        }
        Insert: {
          next_incursion_no?: number
          next_sample_no?: number
          next_site_no?: number
          site_prefix?: string
          workspace_id: string
        }
        Update: {
          next_incursion_no?: number
          next_sample_no?: number
          next_site_no?: number
          site_prefix?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vv_workspace_settings_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: true
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_invitations: {
        Row: {
          accepted_at: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string | null
          revoked_at: string | null
          role: Database["public"]["Enums"]["workspace_role"]
          token_hash: string
          workspace_id: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by?: string | null
          revoked_at?: string | null
          role: Database["public"]["Enums"]["workspace_role"]
          token_hash: string
          workspace_id: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          revoked_at?: string | null
          role?: Database["public"]["Enums"]["workspace_role"]
          token_hash?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_invitations_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_members: {
        Row: {
          created_at: string
          role: Database["public"]["Enums"]["workspace_role"]
          user_id: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          role: Database["public"]["Enums"]["workspace_role"]
          user_id: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          role?: Database["public"]["Enums"]["workspace_role"]
          user_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_members_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_product_events: {
        Row: {
          actor_id: string | null
          enabled: boolean
          id: number
          product: string
          recorded_at: string
          workspace_id: string
        }
        Insert: {
          actor_id?: string | null
          enabled: boolean
          id?: never
          product: string
          recorded_at?: string
          workspace_id: string
        }
        Update: {
          actor_id?: string | null
          enabled?: boolean
          id?: never
          product?: string
          recorded_at?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_product_events_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_products: {
        Row: {
          enabled: boolean
          product: string
          updated_at: string
          updated_by: string | null
          workspace_id: string
        }
        Insert: {
          enabled: boolean
          product: string
          updated_at?: string
          updated_by?: string | null
          workspace_id: string
        }
        Update: {
          enabled?: boolean
          product?: string
          updated_at?: string
          updated_by?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_products_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspaces: {
        Row: {
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["workspace_kind"]
          name: string
          personal_owner_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["workspace_kind"]
          name: string
          personal_owner_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["workspace_kind"]
          name?: string
          personal_owner_id?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_invitation: { Args: { _token: string }; Returns: string }
      add_team_member: {
        Args: { _team: string; _user: string }
        Returns: undefined
      }
      create_invitation: {
        Args: {
          _email: string
          _role: Database["public"]["Enums"]["workspace_role"]
          _ws: string
        }
        Returns: string
      }
      create_team: { Args: { _name: string; _ws: string }; Returns: string }
      ensure_personal_workspace: { Args: never; Returns: string }
      grant_content_role: {
        Args: {
          _role: Database["public"]["Enums"]["content_role"]
          _user: string
        }
        Returns: undefined
      }
      has_content_role: {
        Args: { _roles: Database["public"]["Enums"]["content_role"][] }
        Returns: boolean
      }
      has_product: { Args: { _product: string; _ws: string }; Returns: boolean }
      has_product_access: {
        Args: { _levels: string[]; _product: string; _ws: string }
        Returns: boolean
      }
      has_ws_role: {
        Args: {
          _roles: Database["public"]["Enums"]["workspace_role"][]
          _ws: string
        }
        Returns: boolean
      }
      invitation_for_email: {
        Args: { _token: string }
        Returns: {
          email: string
          expires_at: string
          invitation_id: string
          inviter_email: string
          role: Database["public"]["Enums"]["workspace_role"]
          workspace_id: string
          workspace_name: string
        }[]
      }
      is_member: { Args: { _ws: string }; Returns: boolean }
      is_org_admin: { Args: { _ws: string }; Returns: boolean }
      is_platform_admin: { Args: never; Returns: boolean }
      kp_is_editor: { Args: never; Returns: boolean }
      may_invite: {
        Args: {
          _role: Database["public"]["Enums"]["workspace_role"]
          _ws: string
        }
        Returns: boolean
      }
      my_products: {
        Args: never
        Returns: {
          level: string
          product: string
          workspace_id: string
        }[]
      }
      platform_workspaces: {
        Args: never
        Returns: {
          id: string
          investigations: boolean
          kind: Database["public"]["Enums"]["workspace_kind"]
          members: number
          name: string
          vectovia: boolean
        }[]
      }
      product_level: {
        Args: { _product: string; _ws: string }
        Returns: string
      }
      provision_organisation: {
        Args: { _name: string; _owner: string }
        Returns: string
      }
      record_invitation_email: {
        Args: {
          _error: string
          _invitation: string
          _provider_message_id: string
          _sent_by: string
          _status: string
        }
        Returns: undefined
      }
      reissue_invitation: { Args: { _invitation: string }; Returns: string }
      remove_member: {
        Args: { _user: string; _ws: string }
        Returns: undefined
      }
      remove_team_member: {
        Args: { _team: string; _user: string }
        Returns: undefined
      }
      revoke_content_role: {
        Args: {
          _role: Database["public"]["Enums"]["content_role"]
          _user: string
        }
        Returns: undefined
      }
      revoke_invitation: { Args: { _invitation: string }; Returns: undefined }
      role_in: { Args: { _user: string; _ws: string }; Returns: string }
      set_member_role: {
        Args: {
          _role: Database["public"]["Enums"]["workspace_role"]
          _user: string
          _ws: string
        }
        Returns: undefined
      }
      set_product_access: {
        Args: { _level: string; _product: string; _user: string; _ws: string }
        Returns: undefined
      }
      set_workspace_product: {
        Args: { _enabled: boolean; _product: string; _ws: string }
        Returns: undefined
      }
      transfer_ownership: {
        Args: { _to: string; _ws: string }
        Returns: undefined
      }
      update_team: {
        Args: { _name: string; _team: string }
        Returns: undefined
      }
      vv_can_read_attachment: { Args: { _id: string }; Returns: boolean }
      vv_can_run_incursion: { Args: { _incursion: string }; Returns: boolean }
      vv_can_see_incursion: { Args: { _incursion: string }; Returns: boolean }
      vv_can_see_programme: { Args: { _programme: string }; Returns: boolean }
      vv_can_see_record: {
        Args: { _id: string; _type: string }
        Returns: boolean
      }
      vv_can_see_site: { Args: { _site: string }; Returns: boolean }
      vv_check_time: { Args: { _t: string; _what: string }; Returns: undefined }
      vv_confirm_attachment: {
        Args: { _id: string; _sha256: string; _size_bytes: number }
        Returns: string
      }
      vv_correct_attachment: {
        Args: {
          _caption: string
          _capture_source: string
          _captured_at: string
          _id: string
          _why: string
        }
        Returns: undefined
      }
      vv_correct_visit: {
        Args: {
          _condition: string
          _exposure_end: string
          _exposure_start: string
          _not_completed_reason: string
          _observations: string
          _occurred_at: string
          _officer: string
          _visit: string
          _why: string
        }
        Returns: undefined
      }
      vv_deploy_trap: {
        Args: {
          _id: string
          _interval: number
          _latitude: number
          _longitude: number
          _officer: string
          _placement: string
          _site: string
          _started_at: string
          _trap: string
          _ws: string
        }
        Returns: undefined
      }
      vv_diff: { Args: { _after: Json; _before: Json }; Returns: Json }
      vv_end_deployment: {
        Args: {
          _deployment: string
          _ended_at: string
          _note: string
          _reason: string
        }
        Returns: undefined
      }
      vv_event: {
        Args: {
          _detail: Json
          _id: string
          _kind: string
          _type: string
          _ws: string
        }
        Returns: undefined
      }
      vv_findings_awaiting_review: {
        Args: { _ws: string }
        Returns: {
          council_taxon_id: string
          quantity: number
          result_date: string
          result_id: string
          sample_id: string
          site_id: string
          status: string
          taxon_id: string
          unit: string
        }[]
      }
      vv_has: { Args: { _levels: string[]; _ws: string }; Returns: boolean }
      vv_lib_add_image: {
        Args: {
          _caption: string
          _credit: string
          _file_name: string
          _id: string
          _licence: string
          _sort: number
          _source_url: string
          _version: string
        }
        Returns: string
      }
      vv_lib_publish: { Args: { _version: string }; Returns: undefined }
      vv_lib_review: {
        Args: { _approve: boolean; _note: string; _version: string }
        Returns: undefined
      }
      vv_lib_save_draft: {
        Args: {
          _content: Json
          _kind: string
          _sources: Json
          _subject: string
        }
        Returns: string
      }
      vv_lib_submit: { Args: { _version: string }; Returns: undefined }
      vv_link_incursion: {
        Args: { _id: string; _results: string[]; _sites: string[] }
        Returns: undefined
      }
      vv_log_attachment_access: {
        Args: { _action: string; _actor: string; _id: string }
        Returns: undefined
      }
      vv_log_export: {
        Args: {
          _counts: Json
          _file_name: string
          _format_version: string
          _id: string
          _kind: string
          _scope: Json
          _sha256: string
          _size: number
          _ws: string
        }
        Returns: undefined
      }
      vv_matrix_level: {
        Args: { _consequence: number; _likelihood: number }
        Returns: string
      }
      vv_move_trap: {
        Args: {
          _deployment: string
          _interval: number
          _latitude: number
          _longitude: number
          _moved_at: string
          _new_id: string
          _officer: string
          _placement: string
          _site: string
        }
        Returns: undefined
      }
      vv_open_incursion: {
        Args: {
          _council_taxon: string
          _id: string
          _lead: string
          _results: string[]
          _site: string
          _status: string
          _taxon: string
          _title: string
        }
        Returns: string
      }
      vv_record_notification: {
        Args: {
          _contact: string
          _id: string
          _incursion: string
          _kind: string
          _method: string
          _note: string
          _notified_at: string
          _recipient: string
          _reference: string
        }
        Returns: undefined
      }
      vv_record_visit: {
        Args: {
          _condition: string
          _deployment: string
          _exposure_end: string
          _exposure_start: string
          _id: string
          _observations: string
          _occurred_at: string
          _officer: string
          _outcome: string
          _reason: string
          _samples: Json
        }
        Returns: undefined
      }
      vv_record_workspace: {
        Args: { _id: string; _type: string }
        Returns: string
      }
      vv_refresh_sample_status: {
        Args: { _sample: string }
        Returns: undefined
      }
      vv_register_attachment: {
        Args: {
          _caption: string
          _capture_source: string
          _captured_at: string
          _file_name: string
          _id: string
          _mime_type: string
          _record_id: string
          _record_type: string
          _sha256: string
          _size_bytes: number
        }
        Returns: string
      }
      vv_remove_external_ref: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      vv_reopen_incursion: {
        Args: {
          _id: string
          _incursion: string
          _reason: string
          _status: string
        }
        Returns: undefined
      }
      vv_save_action: {
        Args: {
          _assessment: string
          _detail: string
          _due: string
          _id: string
          _owner: string
          _site: string
          _title: string
        }
        Returns: undefined
      }
      vv_save_assessment: {
        Args: {
          _consequence: number
          _factors: Json
          _final_level: string
          _id: string
          _likelihood: number
          _override_reason: string
          _rationale: string
          _reason: string
          _results: string[]
          _site: string
        }
        Returns: number
      }
      vv_save_council_taxon: {
        Args: {
          _active: boolean
          _common: string
          _id: string
          _scientific: string
          _ws: string
        }
        Returns: undefined
      }
      vv_save_council_trap_type: {
        Args: {
          _active: boolean
          _description: string
          _id: string
          _name: string
          _ws: string
        }
        Returns: undefined
      }
      vv_save_external_ref: {
        Args: {
          _external_id: string
          _id: string
          _note: string
          _record_id: string
          _record_type: string
          _system: string
        }
        Returns: undefined
      }
      vv_save_incursion_task: {
        Args: {
          _detail: string
          _due: string
          _id: string
          _incursion: string
          _owner: string
          _step: string
          _title: string
        }
        Returns: undefined
      }
      vv_save_library_note: {
        Args: {
          _id: string
          _kind: string
          _note: string
          _subject: string
          _ws: string
        }
        Returns: undefined
      }
      vv_save_notify_contact: {
        Args: {
          _active: boolean
          _detail: string
          _id: string
          _kind: string
          _name: string
          _organisation: string
          _ws: string
        }
        Returns: undefined
      }
      vv_save_programme: {
        Args: {
          _description: string
          _ends: string
          _id: string
          _name: string
          _starts: string
          _status: string
          _teams: string[]
          _ws: string
        }
        Returns: undefined
      }
      vv_save_result: {
        Args: {
          _council_taxon: string
          _id: string
          _identified_by: string
          _lab_reference: string
          _laboratory: string
          _method: string
          _quantity: number
          _reason: string
          _result_date: string
          _sample: string
          _status: string
          _taxon: string
          _uncertainty: string
          _unit: string
        }
        Returns: number
      }
      vv_save_site: {
        Args: {
          _access: string
          _description: string
          _id: string
          _latitude: number
          _line_1: string
          _line_2: string
          _longitude: number
          _name: string
          _postcode: string
          _programmes: string[]
          _status: string
          _town: string
          _uprn: string
          _ws: string
        }
        Returns: string
      }
      vv_save_trap: {
        Args: {
          _council_trap_type: string
          _id: string
          _identifier: string
          _notes: string
          _status: string
          _trap_type: string
          _ws: string
        }
        Returns: undefined
      }
      vv_set_action_status: {
        Args: { _id: string; _note: string; _status: string }
        Returns: undefined
      }
      vv_set_incursion_step: {
        Args: { _id: string; _note: string; _status: string; _step: string }
        Returns: undefined
      }
      vv_set_response_area: {
        Args: {
          _id: string
          _lat: number
          _lon: number
          _radius_m: number
          _reason: string
        }
        Returns: undefined
      }
      vv_stand_down: {
        Args: {
          _decided_at: string
          _id: string
          _incursion: string
          _rationale: string
        }
        Returns: undefined
      }
      vv_update_incursion: {
        Args: {
          _council_taxon: string
          _id: string
          _lead: string
          _reason: string
          _status: string
          _taxon: string
          _title: string
        }
        Returns: undefined
      }
      vv_visit_schedule: {
        Args: { _ws: string }
        Returns: {
          deployment_id: string
          last_visit_at: string
          next_due_on: string
          responsible_officer: string
          site_id: string
          started_at: string
          state: string
          trap_id: string
          visit_interval_days: number
        }[]
      }
      write_audit: {
        Args: { _action: string; _detail?: Json; _target: string; _ws: string }
        Returns: undefined
      }
      ws_role_of: { Args: { _ws: string }; Returns: string }
    }
    Enums: {
      content_role: "author" | "reviewer" | "content_admin"
      kp_status:
        | "draft"
        | "in_review"
        | "reviewed"
        | "published"
        | "superseded"
        | "rejected"
        | "withdrawn"
      workspace_kind: "personal" | "organisation"
      workspace_role: "owner" | "admin" | "member"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      content_role: ["author", "reviewer", "content_admin"],
      kp_status: [
        "draft",
        "in_review",
        "reviewed",
        "published",
        "superseded",
        "rejected",
        "withdrawn",
      ],
      workspace_kind: ["personal", "organisation"],
      workspace_role: ["owner", "admin", "member"],
    },
  },
} as const
