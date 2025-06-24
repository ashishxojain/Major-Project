if (ChangeType.Add == ldifEntry.getChangeType() || 
    /* assume "add" by default */ 
    ChangeType.None == ldifEntry.getChangeType()) {
    coreSession.add(new DefaultEntry(
        coreSession.getDirectoryService().getSchemaManager(), 
        ldifEntry.getEntry()));
} else if (ChangeType.Modify == ldifEntry.getChangeType()) {
    coreSession.modify(ldifEntry.getDn(), ldifEntry.getModifications());
} else if (ChangeType.Delete == ldifEntry.getChangeType()) {
    coreSession.delete(ldifEntry.getDn());
} else {
    throw new IllegalStateException();
}

public void disableAnonymousAccess() {
    directoryService.setAllowAnonymousAccess(false);
}

public void enableAnonymousAccess() {
    directoryService.setAllowAnonymousAccess(true);
}

private ApacheDS startDirectoryService(String workDirStr) throws Exception {
    DefaultDirectoryServiceFactory factory = new DefaultDirectoryServiceFactory();
    factory.init(realm);

    directoryService = factory.getDirectoryService();
    directoryService.getChangeLog().setEnabled(false);
    directoryService.setShutdownHookEnabled(false);
    directoryService.setAllowAnonymousAccess(true);

    File workDir = new File(workDirStr);
    if (workDir.exists()) {
        FileUtils.deleteDirectory(workDir);
    }
    InstanceLayout instanceLayout = new InstanceLayout(workDir);
    directoryService.setInstanceLayout(instanceLayout);

    AvlPartition partition = new AvlPartition(directoryService.getSchemaManager());
    partition.setSuffixDn(new Dn(directoryService.getSchemaManager(), baseDn));
    partition.addIndexedAttributes(
        new AvlIndex<>("ou"),
        new AvlIndex<>("uid"),
        new AvlIndex<>("dc"),
        new AvlIndex<>("objectClass")
    );
    partition.initialize();
    directoryService.addPartition(partition);
    directoryService.addLast(new KeyDerivationInterceptor());

    directoryService.shutdown();
    directoryService.startup();

    return this;
}

private ApacheDS startLdapServer(int port) throws Exception {
    this.ldapPort = port;
    ldapServer.setTransports(new TcpTransport(port));
    ldapServer.setDirectoryService(directoryService);

    // Setup SASL mechanisms
    Map<String, MechanismHandler> mechanismHandlerMap = new HashMap<>();
    mechanismHandlerMap.put(SupportedSaslMechanisms.PLAIN, new PlainMechanismHandler());
    mechanismHandlerMap.put(SupportedSaslMechanisms.CRAM_MD5, new CramMd5MechanismHandler());
    mechanismHandlerMap.put(SupportedSaslMechanisms.DIGEST_MD5, new DigestMd5MechanismHandler());
    mechanismHandlerMap.put(SupportedSaslMechanisms.GSSAPI, new GssapiMechanismHandler());
    ldapServer.setSaslMechanismHandlers(mechanismHandlerMap);

    ldapServer.setSaslHost(HOSTNAME_LOCALHOST);
    ldapServer.setSaslRealms(Collections.singletonList(realm));
    // TODO ldapServer.setSaslPrincipal();
    // The base DN containing users that can be SASL authenticated.
    ldapServer.setSearchBaseDn(baseDn);

    ldapServer.start();

    return this;
}

private ApacheDS startKdcServer() throws IOException, KrbException {
    int port = AvailablePortFinder.getNextAvailable(6088);

    File krbConf = new File("target/krb5.conf");
    FileUtils.writeStringToFile(krbConf, ""
        + "[libdefaults]\n"
        + " default_realm = EXAMPLE.ORG\n"
        + "\n"
        + "[realms]\n"
        + " EXAMPLE.ORG = {\n"
        + " kdc = localhost:" + port + "\n"
        + " }\n"
        + "\n"
        + "[domain_realm]\n"
        + " .example.org = EXAMPLE.ORG\n"
        + " example.org = EXAMPLE.ORG\n",
        StandardCharsets.UTF_8.name());

    kdcServer = new KdcServer(krbConf);
    kdcServer.setKdcRealm("EXAMPLE.ORG");
    kdcServer.getKdcConfig().setBoolean(KrbConfigKey.PA_ENC_TIMESTAMP_REQUIRED, false);

    BackendConfig backendConfig = kdcServer;
    backendConfig.setString("host", HOSTNAME_LOCALHOST);
    backendConfig.setString("base_dn", baseDn);
    backendConfig.setInt("port", this.ldapPort);
    backendConfig.setString(KdcConfigKey.KDC_IDENTITY_BACKEND,
        "org.apache.kerby.kerberos.kdc.identitybackend.LdapIdentityBackend");

    kdcServer.setAllowUdp(true);
    kdcServer.setAllowTcp(false);
    kdcServer.setKdcUdpPort(port);
    kdcServer.setKdcHost(HOSTNAME_LOCALHOST);
    kdcServer.init();
    kdcServer.start();

    return this;
}

/**
 * This seems to be required for objectClass posixGroup.
 */
private ApacheDS activateNis() throws Exception {
    directoryService.getAdminSession().modify(
        new Dn("cn=nis,ou=schema"),
        new DefaultModification(ModificationOperation.REPLACE_ATTRIBUTE, "m-disabled", "FALSE")
    );
    return this;
}

