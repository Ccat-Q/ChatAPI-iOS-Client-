# ADR 0001: Maintain a separate compatibility server repository

The iOS client remains independent from the ChatAPI compatibility fork. The fork owns mobile authentication, capability negotiation, and Bark delivery. This keeps upstream merges and iOS releases independently reviewable.
