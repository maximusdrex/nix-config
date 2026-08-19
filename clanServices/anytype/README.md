# Anytype

This Clan service deploys one Anytype network across a nodes host and a storage host.

The nodes role provides these components:

- One sync node
- One coordinator
- One file node
- One consensus node

The storage role provides these components:

- MongoDB
- Redis Stack
- MinIO

Podman Quadlets manage each container. The service pins each container image by tag and digest.

The templates derive from `any-sync-dockercompose` revision `53f4635337524ca8dc5be34cd2840295245c884d`.

See `UPSTREAM_LICENSE.md` for the upstream MIT license.

## Network design

Nginx relays the public Anytype TCP ports without protocol termination.

Podman publishes the public Anytype QUIC ports directly. This path does not use the Nginx UDP proxy.

Every node advertises only public DNS names. The canonical configuration includes TCP and direct QUIC addresses.

One public DNS name with an A record supports IPv4 and DNS64/NAT64 clients.

An AAAA record is unsafe until native IPv6 ingress passes an external test.

The nodes host accepts every public TCP and UDP port through IPv4.

The server and both client files use the same address list.

The bootstrap applies a new configuration only when the canonical node list changes.

The bootstrap records MongoDB's active configuration ID.

The client files retain the generated bootstrap ID. This ID makes each new client fetch the active configuration.

ZeroTier carries only traffic between the nodes host and the storage host.

The nodes host exposes these port pairs:

| Service | TCP | UDP |
| --- | ---: | ---: |
| Sync node | 1001 | 1011 |
| Coordinator | 1004 | 1014 |
| File node | 1005 | 1015 |
| Consensus node | 1006 | 1016 |

The storage ports bind to the storage host ZeroTier address and localhost.

The firewall accepts storage traffic only on the configured private interface.

MongoDB uses password authentication and a replica key file. Redis and MinIO also require shared credentials.

The coordinator allows public network registration. Resource limits reduce abuse but do not provide account approval.

## Resource limits

The configuration sets these limits:

- 10 GiB for the default file allowance
- 100 shared spaces for one account
- 100 GiB for the MinIO bucket quota

The MinIO quota is an administrative limit. It is not a substitute for disk usage checks.

## Initial deployment

This configuration creates a new Anytype network. The previous client file cannot connect to this network.

1. Apply the storage host configuration.

2. Verify the storage services.

   ```console
   systemctl status anytype-mongo.service anytype-redis.service anytype-minio.service anytype-create-bucket.service
   ```

3. Apply the nodes host configuration.

4. Verify the nodes and the proxy.

   ```console
   systemctl status 'anytype-*' nginx.service
   ```

5. Copy the client file from the nodes host through SSH.

   ```console
   scp max@maxschaefer.me:/var/lib/anytype-public/client.yml ./client.yml
   ```

6. Verify the client file headers.

   ```console
   grep -E '^id: [a-f0-9]{24}$' client.yml
   grep -E '^networkId: "N[A-Za-z0-9]+"$' client.yml
   ```

7. Import `client.yml` from the local Files application.

Do not use a browser URL for this file. The service does not publish the file over HTTP.

8. Verify sync from a device outside ZeroTier.

9. Remove `/var/lib/anytype` from the old host only after successful validation.

Do not remove the old state before validation. The old state provides the rollback path.

## Operations

Check all Anytype units on the current host:

```console
systemctl status 'anytype-*'
```

Read a service log:

```console
journalctl -u anytype-coordinator.service
```

Inspect container health:

```console
podman ps --format 'table {{.Names}}\t{{.Status}}'
```

Verify the active and bootstrap configuration IDs:

```console
cat /var/lib/anytype-public/identity/.appliedConfigurationId
yq eval '.id' /var/lib/anytype-public/client.yml
```

The two IDs must differ. The coordinator replaces the bootstrap ID during the first configuration request.

Verify the public TCP listeners on the edge host:

```console
ss -lnt '( sport = :1001 or sport = :1004 or sport = :1005 or sport = :1006 )'
```

Verify the public UDP listeners on the edge host:

```console
ss -lnu '( sport = :1011 or sport = :1014 or sport = :1015 or sport = :1016 )'
```

Verify the public DNS records:

```console
dig +short A anytype.example.com
dig +short AAAA anytype.example.com
```

The A query must return the public IPv4 address. The AAAA query must return no record.

## Persistent data

The nodes host stores its identity, configuration, and local node state under `/var/lib/anytype-public`.

The storage host stores MongoDB, Redis, and MinIO data under `/var/lib/anytype-public`.

Loss of the nodes identity directory creates a different Anytype network.

The service declares each state directory through `clan.core.state.anytype`.

The state declaration enables backup providers to discover the complete Anytype state.

This service does not configure a backup provider or a backup schedule.

## Updates

Update all compatible Anytype image references as one reviewed change. Update each tag and digest together.

Do not enable Podman automatic updates. A mixed image set can break protocol compatibility.
