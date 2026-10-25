# Listen Together party server — builds to one static Go binary.
#
# Any Docker host runs this as-is (Render, Koyeb, Fly.io, a VPS…):
#   docker build -t ifallmusic-party backend/
#   docker run -p 8000:8000 -e PORT=8000 ifallmusic-party
#
# The server reads PORT (default 8000) and binds 0.0.0.0, which is what
# every free host expects. Health check: GET /healthz.
# See DEPLOY.md for the free one-click walkthrough.

FROM golang:1.27-alpine AS build
WORKDIR /src

# Dependencies first so code-only changes rebuild fast.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /party-server .

# Nothing but the binary: no shell, no package manager, runs as non-root.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /party-server /party-server
EXPOSE 8000
ENTRYPOINT ["/party-server"]
