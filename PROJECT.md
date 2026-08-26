# Product brief

B-Town Bus helps Bloomington riders answer five questions quickly: where the bus is, when it reaches a stop, which nearby stop to use, which direction it is going, and whether to leave now.

The frontend consumes only normalized transit types. The Bloomington adapter reads official GTFS/GTFS-Realtime data; the IU adapter validates the public ETA Spot responses. Realtime freshness is explicit, arrivals are never inferred from vehicle speed, and either provider may fail without taking down the other.

The public product is mobile-first, independent, and designed for use while walking. Its current MVP includes a combined map, route filters, live vehicles, nearby stops, stop arrivals, direction labels, favorites, location, walking estimates, leave-now guidance, service alerts, partial-feed recovery, and installable-app metadata.
