export interface Redirect {
  from: string;
  to: string;
  permanent?: boolean;
}

export interface Header {
  name: string;
  value?: string | null;
  on?: string | null;
}

export interface Form {
  from: string;
  to: string;
  then?: string;
}

export interface XmitConfig {
  fallback?: string;
  "404"?: string;
  headers?: Header[];
  redirects?: Redirect[];
  forms?: Form[];
}

export interface BobConfig {
  directory?: string;
  sites?: Record<string, {
    domain: string;
    service: string;
  }>;
}

export interface PackageJson {
  bob?: BobConfig;
}
