package webapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/vyto4ka/vynel/internal/panel/service"
	"github.com/vyto4ka/vynel/internal/panel/subscription"
)

func TestAdminUserFullName(t *testing.T) {
	c, svc, pw := newServer(t)
	if w := c.do("POST", "/api/login", `{"login":"boss","password":"`+pw+`"}`, true); w.Code != http.StatusOK {
		t.Fatalf("login: %d %s", w.Code, w.Body.String())
	}
	const name = "Тестова Анна Примеровна"
	const newName = "Примерова Анна Тестовна"
	admin := func(method, path, body string, out any) {
		t.Helper()
		r := c.do(method, "/api"+path, body, true)
		if r.Code != http.StatusOK {
			t.Fatalf("%s %s: %d %s", method, path, r.Code, r.Body.String())
		}
		if err := json.Unmarshal(r.Body.Bytes(), out); err != nil {
			t.Fatalf("%s %s: %v", method, path, err)
		}
	}
	var u, unnamed User
	admin("POST", "/users", `{"username":"private-test","fullName":"  `+name+`  "}`, &u)
	admin("POST", "/users", `{"username":"without-full-name"}`, &unnamed)
	if u.Username != "private-test" || u.FullName != name || unnamed.FullName != "" {
		t.Fatal("unexpected name after creation")
	}
	var results struct {
		Users []User
		Total int
	}
	query := url.QueryEscape("тЕсТоВа")
	admin("GET", "/users?limit=10&search="+query, "", &results)
	if results.Total != 1 || len(results.Users) != 1 || results.Users[0].ID != u.ID {
		t.Fatalf("private search did not return the named user: %+v", results)
	}
	path := fmt.Sprintf("/users/%d", u.ID)
	var detail struct{ User User }
	admin("PATCH", path, `{"fullName":"`+newName+`"}`, &u)
	admin("PATCH", path, `{"note":"updated"}`, &u)
	admin("GET", path, "", &detail)
	if u.FullName != newName || detail.User.FullName != newName || detail.User.Username != "private-test" {
		t.Fatal("full name was not saved independently of other fields")
	}

	token := apiToken(t, svc, service.ScopeUsersRead, service.ScopeEventsRead)
	checkPrivate := func(r *httptest.ResponseRecorder) {
		t.Helper()
		body := r.Body.String()
		if r.Code != http.StatusOK {
			t.Fatalf("unexpected response: %d %s", r.Code, body)
		}
		if strings.Contains(body, name) || strings.Contains(body, newName) ||
			strings.Contains(body, `"fullName"`) || strings.Contains(body, `"full_name"`) ||
			strings.Contains(body, `"FullName"`) {
			t.Fatal("private full name in a response outside the admin user view")
		}
	}
	for _, url := range []string{path, "/users/export", "/events"} {
		checkPrivate(apiCall(t, c, token, "GET", url, ""))
	}
	match := apiCall(t, c, token, "GET", "/users?search="+url.QueryEscape(newName), "")
	checkPrivate(match)
	var publicResults struct{ Total int }
	if err := json.Unmarshal(match.Body.Bytes(), &publicResults); err != nil || publicResults.Total != 0 {
		t.Fatal("public search matched a private full name")
	}

	row, err := svc.User(t.Context(), u.ID)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("GET", service.DefaultSubPrefix+row.SubToken, nil)
	sub := httptest.NewRecorder()
	subscription.NewHandler(svc, nil).ServeHTTP(sub, req)
	checkPrivate(sub)
	for _, values := range sub.Header() {
		for _, value := range values {
			if strings.Contains(value, newName) {
				t.Fatal("private full name in subscription headers")
			}
		}
	}

	admin("PATCH", path, `{"fullName":""}`, &u)
	admin("GET", path, "", &detail)
	if detail.User.FullName != "" {
		t.Fatal("could not clear the full name")
	}
}
