# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # ---------------------------------------------------------------------------
  # IDENTIDAD Y CONFIGURACIÓN GENERAL DEL NODO
  # ---------------------------------------------------------------------------

  networking.hostName = "nixos-ops-node";

  # Enable networking through NetworkManager.
  networking.networkmanager.enable = true;

  # Time zone and locale.
  time.timeZone = "America/Lima";
  i18n.defaultLocale = "en_US.UTF-8";

  # Console keyboard layout. No graphical environment will be installed.
  console.keyMap = "us";


  # ---------------------------------------------------------------------------
  # NIX Y PAQUETES DEL SISTEMA
  # ---------------------------------------------------------------------------

  # Allow packages whose licenses are classified as unfree.
  nixpkgs.config.allowUnfree = true;

  # Enable modern Nix commands and flakes for reproducible configurations.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Base administration and diagnostic tools.
  environment.systemPackages = with pkgs; [
    mdadm
    git
    curl
    wget
    vim
    nano
    htop
    tree
    jq
    pciutils
    usbutils
    restic
  ];


  # ---------------------------------------------------------------------------
  # USUARIO ADMINISTRATIVO INICIAL
  # ---------------------------------------------------------------------------

  users.users.rencina = {
    isNormalUser = true;
    description = "Renzo Encina";

    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    packages = with pkgs; [ ];
  };

  users.users.infra-admin = {
    isNormalUser = true;
    description = "Infrastructure Administrator";

    extraGroups = [
      "wheel"
    ];

    packages = with pkgs; [ ];
  };

  # ---------------------------------------------------------------------------
  # USUARIO TÉCNICO PARA RESPALDOS
  # ---------------------------------------------------------------------------

  users.users.backup = {
    isSystemUser = true;
    group = "backup";
    description = "Servicio de respaldos Restic";
  };

  users.groups.backup = { };

  # ---------------------------------------------------------------------------
  # ACCESO REMOTO MEDIANTE OPENSSH
  # ---------------------------------------------------------------------------

  services.openssh = {
    enable = true;

    # The firewall port is declared explicitly below.
    openFirewall = false;

    settings = {
      PermitRootLogin = "no";

      # Temporarily enabled until SSH public-key authentication is validated.
      PasswordAuthentication = false;

      # Prevent alternative interactive password authentication.
      KbdInteractiveAuthentication = false;
    };
  };


  # ---------------------------------------------------------------------------
  # FIREWALL
  # ---------------------------------------------------------------------------

  networking.firewall = {
    enable = true;

    # SSH administration. HTTPS will be added when Nginx is configured.
    allowedTCPPorts = [ 
      22
      80
      443
    ];

    allowedUDPPorts = [ ];
  };


  # ---------------------------------------------------------------------------
  # SINCRONIZACIÓN HORARIA
  # ---------------------------------------------------------------------------

  services.chrony.enable = true;

  # ---------------------------------------------------------------------------
  # MONITOREO: PROMETHEUS Y NODE EXPORTER
  # ---------------------------------------------------------------------------

  services.prometheus = {
    enable = true;

    # Prometheus remains internal and is not exposed through the firewall.
    listenAddress = "127.0.0.1";
    port = 9090;

    # Limit local storage consumption for the laboratory PoC.
    retentionTime = "7d";

    exporters.node = {
      enable = true;

      # Node Exporter remains accessible only from the local node.
      listenAddress = "127.0.0.1";
      port = 9100;

      enabledCollectors = [
        "systemd"
      ];
    };

    scrapeConfigs = [
      {
        job_name = "nixos-node";

        static_configs = [
          {
            targets = [
              "127.0.0.1:9100"
            ];
          }
        ];
      }
    ];
  };

  # ---------------------------------------------------------------------------
  # VISUALIZACIÓN: GRAFANA
  # ---------------------------------------------------------------------------

  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
      };

      security = {
        secret_key =
          "$__file{/run/credentials/grafana.service/secret_key}";
      };

      analytics = {
        reporting_enabled = false;
        feedback_links_enabled = false;
      };
    };

    provision = {
      enable = true;

      datasources.settings = {
        apiVersion = 1;

        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:9090";
            isDefault = true;
            editable = false;
          }
        ];
      };
    };
  };

  # ---------------------------------------------------------------------------
  # PROXY INVERSO HTTPS: NGINX
  # ---------------------------------------------------------------------------

  services.nginx = {
    enable = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."nixos-ops-node" = {
      forceSSL = true;

      sslCertificate = "/etc/nixos/certs/nginx.crt";
      sslCertificateKey = "/etc/nixos/certs/nginx.key";

      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
      };
    };
  };

  # systemd entrega el secreto a Grafana en tiempo de ejecución.
  systemd.services.grafana.serviceConfig.LoadCredential =
    "secret_key:/var/lib/secrets/grafana-secret-key";

  # ---------------------------------------------------------------------------
  # ALMACENAMIENTO EXTERNO PARA RESPALDOS RESTIC
  # ---------------------------------------------------------------------------

  fileSystems."/mnt/restic-backup" = {
    device = "/dev/disk/by-uuid/dc19fcd6-ca59-4658-8d04-b094a24a46bf";
    fsType = "ext4";
    options = [ "nofail" ];
  };

  # ---------------------------------------------------------------------------
  # REGISTROS PERSISTENTES
  # ---------------------------------------------------------------------------

  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=200M
    RuntimeMaxUse=100M
  '';


  # ---------------------------------------------------------------------------
  # COMPATIBILIDAD DEL ESTADO DEL SISTEMA
  # ---------------------------------------------------------------------------

  # Keep the release corresponding to the original installation.
  system.stateVersion = "26.05";
}
