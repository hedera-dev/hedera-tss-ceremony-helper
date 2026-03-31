package com.hedera.ceremony.test;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

import java.net.URI;
import java.util.ArrayList;
import java.util.List;

/**
 * Tests S3 read/write permissions for a ceremony participant.
 * <p>
 * Accepts the same 7 positional arguments as the real hedera-cryptography-ceremony JAR
 * so it can be used as a drop-in replacement for validating the environment setup.
 * <p>
 * Reads TSS_CEREMONY_S3_ACCESS_KEY and TSS_CEREMONY_S3_SECRET_KEY from the environment.
 */
public class S3PermissionTest {

    private static int passCount = 0;
    private static int failCount = 0;

    public static void main(String[] args) {
        if (args.length < 5) {
            System.err.println("Usage: S3PermissionTest <PARTICIPANT_ID> <PARTICIPANT_IDS> <REGION> <ENDPOINT> <BUCKET> [KEYS_PATH] [PASSWORD]");
            System.err.println();
            System.err.println("Arguments:");
            System.err.println("  PARTICIPANT_ID    This participant's ID (e.g. 1000000001)");
            System.err.println("  PARTICIPANT_IDS   Comma-separated list of all participant IDs");
            System.err.println("  REGION     S3 bucket region (e.g. us-east1)");
            System.err.println("  ENDPOINT   S3 endpoint URL (e.g. https://storage.googleapis.com)");
            System.err.println("  BUCKET     S3 bucket name");
            System.err.println("  KEYS_PATH  (ignored, accepted for compatibility)");
            System.err.println("  PASSWORD   (ignored, accepted for compatibility)");
            System.exit(1);
        }

        String participantId = args[0];
        String participantIds = args[1];
        String region = args[2];
        String endpoint = args[3];
        String bucket = args[4];

        String accessKey = System.getenv("TSS_CEREMONY_S3_ACCESS_KEY");
        String secretKey = System.getenv("TSS_CEREMONY_S3_SECRET_KEY");

        if (accessKey == null || accessKey.isEmpty() || secretKey == null || secretKey.isEmpty()) {
            System.err.println("Error: TSS_CEREMONY_S3_ACCESS_KEY and TSS_CEREMONY_S3_SECRET_KEY must be set.");
            System.exit(1);
        }

        String otherParticipantId = deriveOtherParticipantId(participantId, participantIds);

        System.out.println("=== Hedera TSS Ceremony - S3 Permission Test ===");
        System.out.println("Participant ID:  " + participantId);
        System.out.println("Other Participants:  " + otherParticipantId);
        System.out.println("S3 Bucket:   " + bucket);
        System.out.println("S3 Region:   " + region);
        System.out.println("S3 Endpoint: " + endpoint);
        System.out.println();

        S3Client s3 = S3Client.builder()
                .region(Region.of(region))
                .endpointOverride(URI.create(endpoint))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(accessKey, secretKey)))
                .serviceConfiguration(S3Configuration.builder()
                        .chunkedEncodingEnabled(false)
                        .build())
                .forcePathStyle(true)
                .build();

        // The 14 paths matching admin-verify-participant-access.sh exactly.
        String p1  = "cycle0/phase2/" + participantId + ".bin/chunk-0001.dat";
        String p2  = "cycle0/phase2/" + participantId + ".bin/chunk-0002.dat";
        String p3  = "cycle0/phase2/" + participantId + ".ready";
        String p4  = "cycle0/phase2/" + participantId + ".claimed";
        String p5  = "cycle0/phase4/" + participantId + ".bin/chunk-0001.dat";
        String p6  = "cycle0/phase4/" + participantId + ".ready";
        String p7  = "cycle0/phase4/" + participantId + ".claimed";
        String p8  = "cycle99/phase2/" + participantId + ".bin/chunk-0001.dat";
        String p9  = "cycle0/phase2/" + participantId + ".bin";
        String p10 = "cycle0/phase2/initial.ready";
        String p11 = "cycle0/phase2/" + otherParticipantId + ".bin/chunk-0001.dat";
        String p12 = "cycle0/phase2/" + otherParticipantId + ".ready";
        String p13 = "cycle0/phase3/" + participantId + ".bin/chunk-0001.dat";
        String p14 = "cycle100/phase2/" + participantId + ".bin/chunk-0001.dat";

        // ── Read checks (14 total) ──
        System.out.println("--- Read checks (14 total) ---");
        for (String path : List.of(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14)) {
            expectReadSuccess(s3, bucket, path);
        }
        System.out.println();

        // ── Write-allowed checks (8 total) ──
        System.out.println("--- Write-allowed checks (8 total) ---");
        List<String> writtenPaths = new ArrayList<>();
        for (String path : List.of(p1, p2, p3, p4, p5, p6, p7, p8)) {
            if (expectWriteSuccess(s3, bucket, path)) {
                writtenPaths.add(path);
            }
        }
        System.out.println();

        // ── Write-denied checks (6 total) ──
        System.out.println("--- Write-denied checks (6 total) ---");
        for (String path : List.of(p9, p10, p11, p12, p13, p14)) {
            expectWriteDenied(s3, bucket, path);
        }
        System.out.println();

        // ── Cleanup written test objects ──
        if (!writtenPaths.isEmpty()) {
            System.out.println("--- Cleaning up test objects ---");
            for (String path : writtenPaths) {
                try {
                    s3.deleteObject(DeleteObjectRequest.builder()
                            .bucket(bucket)
                            .key(path)
                            .build());
                    System.out.println("  deleted " + path);
                } catch (S3Exception e) {
                    System.out.println("  failed to delete " + path + " (HTTP " + e.statusCode() + ")");
                }
            }
            System.out.println();
        }

        // ── Summary ──
        int total = passCount + failCount;
        System.out.println("=== Summary ===");
        System.out.println(passCount + "/" + total + " checks passed, " + failCount + " failed.");

        if (failCount > 0) {
            System.out.println("Some S3 permission checks FAILED.");
            System.exit(1);
        } else {
            System.out.println("All S3 permission checks passed.");
        }
    }

    private static String deriveOtherParticipantId(String participantId, String participantIds) {
        String[] ids = participantIds.split(",");
        for (String id : ids) {
            String trimmed = id.trim();
            if (!trimmed.equals(participantId)) {
                return trimmed;
            }
        }
        // Fallback: use a different participant ID
        return "1000000002".equals(participantId) ? "1000000003" : "1000000002";
    }

    /**
     * Read check: HeadObject. 200 or 404 = PASS (IAM allows the read).
     * 403 = FAIL (read permission denied).
     */
    private static void expectReadSuccess(S3Client s3, String bucket, String key) {
        try {
            s3.headObject(HeadObjectRequest.builder()
                    .bucket(bucket)
                    .key(key)
                    .build());
            pass("read", key);
        } catch (S3Exception e) {
            int status = e.statusCode();
            if (status == 404) {
                // Object does not exist, but the read was allowed by IAM.
                pass("read", key);
            } else if (status == 403) {
                fail("read", key, "expected success, got HTTP 403");
            } else {
                fail("read", key, "unexpected HTTP " + status);
            }
        }
    }

    /**
     * Write check (expected success): PutObject with a small payload.
     * 200/201 = PASS. 403 = FAIL.
     */
    private static boolean expectWriteSuccess(S3Client s3, String bucket, String key) {
        try {
            s3.putObject(
                    PutObjectRequest.builder()
                            .bucket(bucket)
                            .key(key)
                            .contentType("text/plain")
                            .build(),
                    RequestBody.fromString("test"));
            pass("write", key);
            return true;
        } catch (S3Exception e) {
            fail("write", key, "expected success, got HTTP " + e.statusCode());
            return false;
        }
    }

    /**
     * Write check (expected denial): PutObject. 401/403 = PASS. 200/201 = FAIL.
     */
    private static void expectWriteDenied(S3Client s3, String bucket, String key) {
        try {
            s3.putObject(
                    PutObjectRequest.builder()
                            .bucket(bucket)
                            .key(key)
                            .contentType("text/plain")
                            .build(),
                    RequestBody.fromString("test"));
            // Write succeeded — this is a failure (permission should have denied it).
            fail("deny", key, "expected 403, but write succeeded");
            // Attempt cleanup since we accidentally wrote.
            try {
                s3.deleteObject(DeleteObjectRequest.builder()
                        .bucket(bucket)
                        .key(key)
                        .build());
            } catch (S3Exception ignored) {
                // best-effort cleanup
            }
        } catch (S3Exception e) {
            int status = e.statusCode();
            if (status == 401 || status == 403) {
                pass("deny", key);
            } else {
                fail("deny", key, "expected 401/403, got HTTP " + status);
            }
        }
    }

    private static void pass(String kind, String key) {
        passCount++;
        System.out.println("PASS  " + padRight(kind, 6) + key);
    }

    private static void fail(String kind, String key, String reason) {
        failCount++;
        System.out.println("FAIL  " + padRight(kind, 6) + key + " (" + reason + ")");
    }

    private static String padRight(String s, int width) {
        if (s.length() >= width) return s;
        return s + " ".repeat(width - s.length());
    }
}
