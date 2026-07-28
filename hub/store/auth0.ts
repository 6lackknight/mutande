import * as jose from "jose";
import { unauthorized } from "./errors.ts";
import type { Auth0Claims } from "./types.ts";

export interface TokenVerifier {
  verifyAccessToken(token: string): Promise<Auth0Claims>;
}

export function createAuth0Verifier(config: {
  domain: string;
  audience: string;
}): TokenVerifier {
  const issuer = `https://${config.domain}/`;
  const jwks = jose.createRemoteJWKSet(
    new URL(`https://${config.domain}/.well-known/jwks.json`),
  );

  return {
    async verifyAccessToken(token: string): Promise<Auth0Claims> {
      try {
        const { payload } = await jose.jwtVerify(token, jwks, {
          issuer,
          audience: config.audience,
        });
        const sub = payload.sub;
        if (typeof sub !== "string" || !sub) {
          throw unauthorized("Invalid token: missing sub");
        }
        const email = typeof payload.email === "string" ? payload.email : undefined;
        return { sub, email };
      } catch (e) {
        if (e instanceof Error && e.message.includes("missing sub")) throw e;
        throw unauthorized("Invalid or expired token");
      }
    },
  };
}

/** Test helper: local RSA keypair + signer for Auth0-shaped access tokens. */
export async function createTestTokenVerifier(config: {
  issuer?: string;
  audience?: string;
} = {}): Promise<{
  verifier: TokenVerifier;
  signToken: (claims: Auth0Claims) => Promise<string>;
}> {
  const issuer = config.issuer ?? "https://test.auth0.local/";
  const audience = config.audience ?? "https://hub.mutande.test";
  const { publicKey, privateKey } = await jose.generateKeyPair("RS256");
  const jwk = await jose.exportJWK(publicKey);
  jwk.alg = "RS256";
  jwk.use = "sig";
  jwk.kid = "test-key";
  const jwks = jose.createLocalJWKSet({ keys: [jwk] });

  const verifier: TokenVerifier = {
    async verifyAccessToken(token: string): Promise<Auth0Claims> {
      try {
        const { payload } = await jose.jwtVerify(token, jwks, { issuer, audience });
        const sub = payload.sub;
        if (typeof sub !== "string" || !sub) {
          throw unauthorized("Invalid token: missing sub");
        }
        const email = typeof payload.email === "string" ? payload.email : undefined;
        return { sub, email };
      } catch (e) {
        if (e instanceof Error && e.message.includes("missing sub")) throw e;
        throw unauthorized("Invalid or expired token");
      }
    },
  };

  const signToken = async (claims: Auth0Claims): Promise<string> => {
    const builder = new jose.SignJWT({ email: claims.email })
      .setProtectedHeader({ alg: "RS256", kid: "test-key" })
      .setSubject(claims.sub)
      .setIssuer(issuer)
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime("1h");
    return builder.sign(privateKey);
  };

  return { verifier, signToken };
}
