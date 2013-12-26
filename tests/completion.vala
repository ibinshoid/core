/*
 Copyright (C) 2012 Christian Dywan <christian@twotoasts.de>

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2.1 of the License, or (at your option) any later version.

 See the file COPYING for the full license text.
*/

class TestCompletion : Midori.Completion {
    public bool test_can_complete { get; set; }
    public uint test_suggestions { get; set; }

    public TestCompletion () {
    }

    public override void prepare (GLib.Object app) {
    }

    public override bool can_complete (string text) {
        return test_can_complete;
    }

    public override bool can_action (string action) {
        return false;
    }

    public override async List<Midori.Suggestion>? complete (string text, string? action, Cancellable cancellable) {
        var suggestions = new List<Midori.Suggestion> ();
        if (test_suggestions == 0)
            return null;
        if (test_suggestions >= 1)
            suggestions.append (new Midori.Suggestion ("about:first", "First"));
        if (test_suggestions >= 2)
            suggestions.append (new Midori.Suggestion ("about:second", "Second"));
        if (test_suggestions >= 3)
            suggestions.append (new Midori.Suggestion ("about:third", "Third"));
        if (cancellable.is_cancelled ())
            return null;
        return suggestions;
    }
}

void completion_autocompleter () {
    var app = new Midori.App ();
    var autocompleter = new Midori.Autocompleter (app);
    assert (!autocompleter.can_complete (""));
    var completion = new TestCompletion ();
    autocompleter.add (completion);
    completion.test_can_complete = false;
    assert (!autocompleter.can_complete (""));
    completion.test_can_complete = true;
    assert (autocompleter.can_complete (""));

    completion.test_suggestions = 0;
    autocompleter.complete.begin ("");
    var loop = MainContext.default ();
    do { loop.iteration (true); } while (loop.pending ());
    assert (autocompleter.model.iter_n_children (null) == 0);

    completion.test_suggestions = 1;
    autocompleter.complete.begin ("");
    do { loop.iteration (true); } while (loop.pending ());
    assert (autocompleter.model.iter_n_children (null) == 1);

    /* Order */
    completion.test_suggestions = 2;
    autocompleter.complete.begin ("");
    do { loop.iteration (true); } while (loop.pending ());
    assert (autocompleter.model.iter_n_children (null) == 2);
    Gtk.TreeIter iter_first;
    autocompleter.model.get_iter_first (out iter_first);
    string title;
    autocompleter.model.get (iter_first, Midori.Autocompleter.Columns.MARKUP, out title);
    if (title != "First")
        error ("Expected %s but got %s", "First", title);

    /* Cancellation */
    autocompleter.complete.begin ("");
    completion.test_suggestions = 3;
    autocompleter.complete.begin ("");
    do { loop.iteration (true); } while (loop.pending ());
    int n = autocompleter.model.iter_n_children (null);
    if (n != 3)
        error ("Expected %d but got %d", 3, n);
}

async void complete_history (Midori.HistoryDatabase history) {
    try {
        history.insert ("http://example.com", "Ejemplo", 0, 0);
    } catch (Error error) {
        assert_not_reached ();
    }
    var cancellable = new Cancellable ();
    var results = yield history.list_by_count_with_bookmarks ("example", 1, cancellable);
    assert (results.length () == 1);
    var first = results.nth_data (0);
    assert (first.title == "Ejemplo");
    results = yield history.list_by_count_with_bookmarks ("ejemplo", 1, cancellable);
    assert (results.length () == 1);
    first = results.nth_data (0);
    assert (first.title == "Ejemplo");
    complete_history_done = true;
}

bool complete_history_done = false;
void completion_history () {
    var app = new Midori.App ();
    Midori.HistoryDatabase history;
    try {
        var bookmarks_database = new Midori.BookmarksDatabase ();
        assert (bookmarks_database.db != null);
        history = new Midori.HistoryDatabase (app);
        assert (history.db != null);
        history.clear (0);
    } catch (Midori.DatabaseError error) {
        assert_not_reached();
    }

    Midori.Test.grab_max_timeout ();
    var loop = MainContext.default ();
    complete_history.begin (history);
    do { loop.iteration (true); } while (!complete_history_done);
    Midori.Test.release_max_timeout ();
}

struct TestCaseRender {
    public string keys;
    public string uri;
    public string title;
    public string expected_uri;
    public string expected_title;
}

const TestCaseRender[] renders = {
    { "debian", "planet.debian.org", "Planet Debian", "planet.<b>debian</b>.org", "Planet <b>Debian</b>" },
    { "p debian o", "planet.debian.org", "Planet Debian", "<b>p</b>lanet.<b>debian</b>.<b>o</b>rg", "Planet Debian" },
    { "pla deb o", "planet.debian.org", "Planet Debian", "<b>pla</b>net.<b>deb</b>ian.<b>o</b>rg", "Planet Debian" },
    { "ebi", "planet.debian.org", "Planet Debian", "planet.d<b>ebi</b>an.org", "Planet D<b>ebi</b>an" },
    { "an ebi", "planet.debian.org", "Planet Debian", "pl<b>an</b>et.d<b>ebi</b>an.org", "Pl<b>an</b>et D<b>ebi</b>an" }
};

void completion_location_action () {
    foreach (var spec in renders) {
        string uri = Midori.LocationAction.render_uri (spec.keys.split (" ", 0), spec.uri);
        string title = Midori.LocationAction.render_title (spec.keys.split (" ", 0), spec.title);
        if (uri != spec.expected_uri || title != spec.expected_title)
            error ("\nExpected: %s/ %s\nInput   : %s/ %s/ %s\nResult  : %s/ %s",
                   spec.expected_uri, spec.expected_title,
                   spec.keys, spec.uri, spec.title, uri, title);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Midori.App.setup (ref args, null);
    Midori.Paths.init (Midori.RuntimeMode.NORMAL, null);
    Test.add_func ("/completion/autocompleter", completion_autocompleter);
    Test.add_func ("/completion/history", completion_history);
    Test.add_func ("/completion/location-action", completion_location_action);
    Test.run ();
}

